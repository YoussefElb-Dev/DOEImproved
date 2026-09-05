import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_palette.dart';
import '../models/academic_history.dart';
import '../models/archive_models.dart';
import '../models/grade_models.dart';
import '../models/portal_snapshot.dart';
import '../models/schedule_models.dart';
import '../models/normalized_transcript.dart';
import '../services/analytics_service.dart';
import '../services/auth_webview_service.dart';
import '../services/document_service.dart';
import '../services/calculator_service.dart';
import '../services/grade_data_service.dart';
import '../services/portal_repository.dart';
import '../services/transcript/normalized_transcript_parser.dart';
import '../services/transcript/transcript_analytics.dart';
import '../services/transcript/transcript_import_service.dart';
import 'archive_store.dart';
import 'settings_store.dart';
import 'transcript_store.dart';

// ─────────────────────────── services ───────────────────────────

final authServiceProvider = Provider<AuthWebViewService>(
  (ref) => AuthWebViewService(),
);

final portalRepositoryProvider = Provider<PortalRepository>((ref) {
  final repo = PortalRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final calculatorProvider = Provider<CalculatorService>(
  (ref) => const CalculatorService(),
);

/// On-device storage: the offline cache, the dated archive, and the PDFs.
final archiveStoreProvider = Provider<ArchiveStore>((ref) => ArchiveStore());

final transcriptStoreProvider =
    Provider<TranscriptStore>((ref) => TranscriptStore());

final transcriptImportServiceProvider = Provider<TranscriptImportService>(
  (ref) => const TranscriptImportService(),
);

final transcriptAnalyticsProvider = Provider<TranscriptAnalytics>(
  (ref) => const TranscriptAnalytics(),
);

final documentServiceProvider = Provider<DocumentService>((ref) {
  final service = DocumentService();
  ref.onDispose(service.dispose);
  return service;
});

// ─────────────────────────── session ───────────────────────────

/// The captured SSO cookies. Empty means "not signed in", which is what
/// [AuthGate] keys off to show the login WebView.
final sessionProvider =
    AsyncNotifierProvider<SessionController, Map<String, String>>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() =>
      ref.read(authServiceProvider).restoreSession();

  /// Called when the login WebView completes and hands us fresh cookies.
  void adopt(Map<String, String> cookies) => state = AsyncData(cookies);

  /// Folds in cookies from a second sign-in, such as the document site.
  Future<void> addCookies(Map<String, String> extra) async {
    if (extra.isEmpty) return;
    final merged = await ref.read(authServiceProvider).mergeSession(extra);
    state = AsyncData(merged);
  }

  /// The portal rejected our cookies — drop them so the UI re-authenticates.
  void markExpired() {
    if (state.valueOrNull?.isEmpty ?? false) return;
    state = const AsyncData({});
  }

  /// Clears the session and the offline cache.
  ///
  /// The dated archive and the saved PDFs are deliberately left alone: they
  /// are the record the DOE no longer keeps, and losing them to a routine
  /// sign-out would defeat the point of saving them. The archive screen has
  /// its own explicit delete.
  Future<void> signOut() async {
    await ref.read(authServiceProvider).clearSession();
    await ref.read(archiveStoreProvider).clearSnapshot();
    state = const AsyncData({});
  }
}

// ─────────────────────────── portal data ───────────────────────────

/// How often a foregrounded app re-pulls the portal on its own.
const Duration kAutoRefreshInterval = Duration(minutes: 5);

/// The single source of truth for every tab. One sync populates grades,
/// schedule, transcript and work together, so the whole app is consistent.
final portalProvider =
    AsyncNotifierProvider<PortalController, PortalSnapshot>(
  PortalController.new,
);

class PortalController extends AsyncNotifier<PortalSnapshot> {
  Timer? _timer;

  @override
  Future<PortalSnapshot> build() async {
    final cookies = await ref.watch(sessionProvider.future);

    _timer?.cancel();
    ref.onDispose(() => _timer?.cancel());

    if (cookies.isEmpty) return PortalRepository.demoSnapshot();

    _timer = Timer.periodic(kAutoRefreshInterval, (_) => refresh());

    // Show the last good sync straight away, then catch up behind it, so the
    // app opens instantly and still works with no signal.
    final cached = await ref.read(archiveStoreProvider).readSnapshot();
    if (cached != null) {
      Future<void>.microtask(refresh);
      return cached;
    }
    return _loadAndPersist(cookies);
  }

  /// Re-pulls the portal while leaving the current data on screen, so a
  /// refresh never flashes the UI back to skeletons — and a failed refresh
  /// keeps showing what was already there rather than blanking the app.
  Future<void> refresh() async {
    final previous = state;
    final cookies = ref.read(sessionProvider).valueOrNull ?? const {};
    state =
        const AsyncValue<PortalSnapshot>.loading().copyWithPrevious(previous);
    final next = await AsyncValue.guard(() => _loadAndPersist(cookies));
    state = next.copyWithPrevious(previous);
  }

  /// Loads, fills gaps from the archive, then writes both the cache and the
  /// report for the day.
  Future<PortalSnapshot> _loadAndPersist(Map<String, String> cookies) async {
    final store = ref.read(archiveStoreProvider);
    var snapshot = await ref.read(portalRepositoryProvider).load(cookies);
    if (!snapshot.isLive) return snapshot;

    // The portal takes the transcript down between terms. This app does not.
    if (snapshot.transcript.isEmpty) {
      final remembered = await store.latestTranscript();
      if (remembered.isNotEmpty) {
        snapshot = snapshot.copyWith(transcript: remembered);
      }
    }

    await store.saveSnapshot(snapshot);
    final wrote = await store.recordReport(
      ArchivedReport.fromSnapshot(snapshot, term: _termOf(snapshot)),
    );
    if (wrote) ref.invalidate(archiveReportsProvider);
    return snapshot;
  }

  String _termOf(PortalSnapshot snapshot) {
    final series =
        ref.read(analyticsProvider).termGpaSeries(snapshot.transcript);
    return series.isEmpty ? '' : series.last.term;
  }

  /// True while a refresh is in flight over already-rendered data.
  bool get isRefreshing => state.isLoading && state.hasValue;
}

// ─────────────────── derived views onto the snapshot ───────────────────
//
// Each tab watches only the slice it renders, so a schedule change does not
// rebuild the grades list.

final _snapshot = Provider<PortalSnapshot?>(
  (ref) => ref.watch(portalProvider).valueOrNull,
);

final studentProfileProvider = Provider<StudentProfile?>(
  (ref) => ref.watch(_snapshot.select((s) => s?.profile)),
);

final courseListProvider = Provider<List<Course>>(
  (ref) => ref.watch(_snapshot.select((s) => s?.courses)) ?? const [],
);

final scheduleProvider = Provider<DaySchedule?>(
  (ref) => ref.watch(_snapshot.select((s) => s?.schedule)),
);

/// Reviewed, versioned transcript files stored privately on the device.
final transcriptRecordsProvider =
    FutureProvider<List<NormalizedTranscript>>((ref) async {
  final transcriptStore = ref.read(transcriptStoreProvider);
  final archiveStore = ref.read(archiveStoreProvider);
  var records = await transcriptStore.list();
  final importedDocumentIds = records
      .map((record) => record.sourceDocumentId)
      .whereType<String>()
      .toSet();
  var importedExistingDocument = false;

  // Upgrade path for PDFs downloaded by an older Gradly build. Their raw text
  // is already on the phone, so parse it into the normalized library once and
  // make it useful without asking the student to download it again.
  for (final document in await archiveStore.listDocuments()) {
    if (document.kind != 'transcript' ||
        importedDocumentIds.contains(document.id)) {
      continue;
    }
    final rawText = await archiveStore.readDocumentText(document.id);
    if (rawText == null) continue;
    final parsed = const NormalizedTranscriptParser().parse(
      rawText: rawText,
      sourceFileName: document.title,
      sourceDocumentId: document.id,
      importedAt: document.savedAt,
    );
    if (!parsed.canSave) {
      debugPrint(
        'Saved transcript ${document.id} could not be normalized: '
        '${parsed.validationErrors.join('; ')}',
      );
      continue;
    }
    await transcriptStore.save(parsed.transcript);
    importedDocumentIds.add(document.id);
    importedExistingDocument = true;
  }

  if (importedExistingDocument) records = await transcriptStore.list();
  return records;
});

final _portalTranscriptProvider = Provider<List<TranscriptRecord>>(
  (ref) => ref.watch(_snapshot.select((s) => s?.transcript)) ?? const [],
);

/// One durable academic history made from saved PDFs, manual imports, and the
/// older portal transcript feed. Normalized PDF data wins when both contain
/// the same class because it carries official cumulative totals and flags.
final academicHistoryProvider = Provider<AsyncValue<AcademicHistory>>((ref) {
  final saved = ref.watch(transcriptRecordsProvider);
  final portalRows = ref.watch(_portalTranscriptProvider);
  return saved.when(
    data: (records) => AsyncData(
      AcademicHistory.combine(normalized: records, legacy: portalRows),
    ),
    loading: () => portalRows.isEmpty
        ? const AsyncLoading()
        : AsyncData(AcademicHistory.combine(legacy: portalRows)),
    error: (error, stackTrace) => portalRows.isEmpty
        ? AsyncError(error, stackTrace)
        : AsyncData(AcademicHistory.combine(legacy: portalRows)),
  );
});

/// The effective transcript also drives analytics, so imported history is
/// reflected throughout the app instead of living only in its library.
final transcriptProvider = Provider<List<TranscriptRecord>>((ref) {
  final history = ref.watch(academicHistoryProvider).valueOrNull;
  return history?.transcriptRecords ?? ref.watch(_portalTranscriptProvider);
});

/// Outstanding work, soonest first — what the grades feed and calendar show.
final workItemsProvider = Provider<List<WorkItem>>(
  (ref) => ref.watch(_snapshot.select((s) => s?.openWork)) ?? const [],
);

/// Everything the portal published, including items already handed in. The
/// assignments screen sorts by status, so it needs the completed ones too.
final allWorkItemsProvider = Provider<List<WorkItem>>(
  (ref) => ref.watch(_snapshot.select((s) => s?.work)) ?? const [],
);

final dataSourceProvider = Provider<DataSource?>(
  (ref) => ref.watch(_snapshot.select((s) => s?.source)),
);

final lastSyncedProvider = Provider<DateTime?>(
  (ref) => ref.watch(_snapshot.select((s) => s?.syncedAt)),
);

/// Drives the pulsing dot in the header.
final syncIndicatorProvider = Provider<bool>(
  (ref) => ref.watch(portalProvider).isLoading,
);

// ─────────────────────────── profile image ───────────────────────────

final profileImageProvider =
    StateNotifierProvider<ProfileImageNotifier, String?>(
  (ref) => ProfileImageNotifier(),
);

class ProfileImageNotifier extends StateNotifier<String?> {
  ProfileImageNotifier() : super(null) {
    SettingsStore.profileImagePath().then((p) {
      if (mounted) state = p.isEmpty ? null : p;
    });
  }

  Future<void> pick() async {
    final p = await SettingsStore.pickAndSaveProfileImage();
    if (p != null && mounted) state = p;
  }

  Future<void> clear() async {
    await SettingsStore.clearProfileImage();
    if (mounted) state = null;
  }
}

// ─────────────────────────── theme ───────────────────────────

/// The active theme. Persisted, so a choice survives a restart.
final themeProvider = StateNotifierProvider<ThemeNotifier, AppPalette>(
  (ref) => ThemeNotifier(),
);

class ThemeNotifier extends StateNotifier<AppPalette> {
  ThemeNotifier() : super(AppPalette.midnight) {
    SettingsStore.themeId().then((id) {
      if (mounted && id != null) state = AppPalette.byName(id);
    });
  }

  Future<void> select(AppThemeId id) async {
    state = AppPalette.byId(id);
    await SettingsStore.saveThemeId(id.name);
  }
}

// ─────────────────────────── analytics ───────────────────────────

final analyticsProvider = Provider<AnalyticsService>(
  (ref) => const AnalyticsService(),
);

/// Credit-weighted GPA per term, oldest first — the overview trend chart.
final termGpaSeriesProvider = Provider<List<TermGpa>>((ref) {
  final transcript = ref.watch(transcriptProvider);
  return ref.watch(analyticsProvider).termGpaSeries(transcript);
});

/// How many marks land in each letter band.
final gradeDistributionProvider = Provider<Map<String, int>>((ref) {
  final service = ref.watch(analyticsProvider);
  return service.gradeDistribution(
    ref.watch(transcriptProvider),
    ref.watch(courseListProvider),
  );
});

/// Average score per inferred subject area — the radar chart.
final subjectPerformanceProvider = Provider<List<SubjectScore>>((ref) {
  return ref.watch(analyticsProvider).subjectPerformance(
        ref.watch(courseListProvider),
      );
});

/// The best-scoring course this term.
final topPerformerProvider = Provider<Course?>((ref) {
  return ref.watch(analyticsProvider).topPerformer(
        ref.watch(courseListProvider),
      );
});

/// Work due, grouped by the calendar day it falls on.
final workByDayProvider = Provider<Map<DateTime, List<WorkItem>>>((ref) {
  final out = <DateTime, List<WorkItem>>{};
  final work = ref.watch(_snapshot.select((s) => s?.work)) ?? const <WorkItem>[];
  for (final w in work) {
    final day = DateTime(w.dueDate.year, w.dueDate.month, w.dueDate.day);
    out.putIfAbsent(day, () => []).add(w);
  }
  for (final list in out.values) {
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }
  return out;
});

// ─────────────────────────── saved history ───────────────────────────

/// Every dated report on the device, newest first.
final archiveReportsProvider =
    FutureProvider<List<ArchivedReportMeta>>((ref) async {
  return ref.read(archiveStoreProvider).listReports();
});

final archivedReportProvider =
    FutureProvider.family<ArchivedReport?, String>((ref, id) async {
  return ref.read(archiveStoreProvider).readReport(id);
});

/// PDFs downloaded from the DOE and kept on the device.
final savedDocumentsProvider =
    FutureProvider<List<SavedDocument>>((ref) async {
  ref.watch(documentSyncProvider);
  return ref.read(archiveStoreProvider).listDocuments();
});

final storageUsageProvider = FutureProvider<int>((ref) async {
  ref.watch(archiveReportsProvider);
  ref.watch(documentSyncProvider);
  return ref.read(archiveStoreProvider).totalBytes();
});

/// Downloads the documents the DOE publishes and stores them on the device.
final documentSyncProvider = StateNotifierProvider<DocumentSyncNotifier,
    AsyncValue<DocumentSyncResult?>>(DocumentSyncNotifier.new);

class DocumentSyncNotifier
    extends StateNotifier<AsyncValue<DocumentSyncResult?>> {
  DocumentSyncNotifier(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  /// Tries to read the document list straight over HTTP.
  ///
  /// Works only when the page is server-rendered. The document site builds its
  /// list in JavaScript, so this usually finds nothing and the browser screen
  /// does the real work — but it costs one request and needs no interaction.
  Future<void> run() async {
    await _perform((service, cookies, store) => service.sync(cookies, store));
  }

  /// Downloads the documents the in-page scan turned up.
  Future<void> saveFound(List<DocumentLink> links) async {
    await _perform(
      (service, cookies, store) => service.downloadAll(links, cookies, store),
    );
  }

  Future<void> _perform(
    Future<DocumentSyncResult> Function(
      DocumentService service,
      Map<String, String> cookies,
      ArchiveStore store,
    ) work,
  ) async {
    if (state.isLoading) return;
    state = const AsyncLoading();

    final cookies = _ref.read(sessionProvider).valueOrNull ?? const {};
    final store = _ref.read(archiveStoreProvider);

    state = await AsyncValue.guard(() async {
      final result = await work(
        _ref.read(documentServiceProvider),
        cookies,
        store,
      );

      // A transcript read out of a PDF is worth keeping even when the portal
      // publishes none — that is the reason for reading it at all.
      if (result.transcript.isNotEmpty) {
        final snapshot = _ref.read(portalProvider).valueOrNull;
        if (snapshot != null) {
          await store.recordReport(
            ArchivedReport.fromSnapshot(
              snapshot.copyWith(transcript: result.transcript),
            ),
          );
        }
      }
      if (result.normalizedTranscripts.isNotEmpty) {
        final transcriptStore = _ref.read(transcriptStoreProvider);
        for (final transcript in result.normalizedTranscripts) {
          await transcriptStore.save(transcript);
        }
        _ref.invalidate(transcriptRecordsProvider);
      }
      return result;
    });

    _ref.invalidate(archiveReportsProvider);
  }
}

// ─────────────────────────── lifecycle ───────────────────────────

class TranscriptImportUiState {
  const TranscriptImportUiState({
    this.stage = TranscriptImportStage.idle,
    this.draft,
    this.saved,
    this.logs = const [],
    this.error,
    this.busy = false,
  });

  final TranscriptImportStage stage;
  final TranscriptImportDraft? draft;
  final NormalizedTranscript? saved;
  final List<TranscriptPipelineLog> logs;
  final String? error;
  final bool busy;

  TranscriptImportUiState copyWith({
    TranscriptImportStage? stage,
    TranscriptImportDraft? draft,
    NormalizedTranscript? saved,
    List<TranscriptPipelineLog>? logs,
    String? error,
    bool clearError = false,
    bool? busy,
  }) {
    return TranscriptImportUiState(
      stage: stage ?? this.stage,
      draft: draft ?? this.draft,
      saved: saved ?? this.saved,
      logs: logs ?? this.logs,
      error: clearError ? null : error ?? this.error,
      busy: busy ?? this.busy,
    );
  }
}

final transcriptImportProvider = StateNotifierProvider<TranscriptImportNotifier,
    TranscriptImportUiState>(TranscriptImportNotifier.new);

class TranscriptImportNotifier extends StateNotifier<TranscriptImportUiState> {
  TranscriptImportNotifier(this._ref) : super(const TranscriptImportUiState());

  final Ref _ref;

  Future<void> pick() async {
    if (state.busy) return;
    state = const TranscriptImportUiState(
      stage: TranscriptImportStage.picker,
      busy: true,
    );
    try {
      final draft = await _ref.read(transcriptImportServiceProvider).pickAndParse(
        onLog: (entry) {
          if (!mounted) return;
          state = state.copyWith(
            stage: entry.stage,
            logs: [...state.logs, entry],
          );
        },
      );
      if (!mounted) return;
      if (draft == null) {
        state = state.copyWith(
          stage: TranscriptImportStage.cancelled,
          busy: false,
        );
        return;
      }
      state = state.copyWith(
        stage: TranscriptImportStage.review,
        draft: draft,
        busy: false,
        clearError: true,
      );
    } on TranscriptImportException catch (error, stackTrace) {
      debugPrint('Transcript import UI failed: $error\n$stackTrace');
      if (!mounted) return;
      state = state.copyWith(
        stage: TranscriptImportStage.failed,
        error: error.userMessage,
        busy: false,
        logs: [
          ...state.logs,
          TranscriptPipelineLog(
            stage: TranscriptImportStage.failed,
            message: error.userMessage,
            time: DateTime.now(),
          ),
        ],
      );
    }
  }

  Future<NormalizedTranscript?> confirm(NormalizedTranscript edited) async {
    final draft = state.draft;
    if (draft == null || state.busy) return null;
    _append(
      TranscriptImportStage.persist,
      'Saving the reviewed record and original PDF on this device.',
      busy: true,
    );
    try {
      final saved = await _ref.read(transcriptStoreProvider).save(
            edited,
            sourceBytes: draft.sourceBytes,
          );
      _ref.invalidate(transcriptRecordsProvider);
      _append(
        TranscriptImportStage.rerender,
        'Reloading the transcript dashboard from saved storage.',
      );
      await _ref.read(transcriptRecordsProvider.future);
      _append(
        TranscriptImportStage.complete,
        'Transcript saved and displayed successfully.',
        busy: false,
        saved: saved,
      );
      return saved;
    } on TranscriptStorageException catch (error, stackTrace) {
      debugPrint('Transcript persistence failed: $error\n$stackTrace');
      _append(
        TranscriptImportStage.failed,
        error.message,
        busy: false,
        error: error.message,
      );
      return null;
    }
  }

  void reset() => state = const TranscriptImportUiState();

  void _append(
    TranscriptImportStage stage,
    String message, {
    bool? busy,
    String? error,
    NormalizedTranscript? saved,
  }) {
    if (!mounted) return;
    final entry = TranscriptPipelineLog(
      stage: stage,
      message: message,
      time: DateTime.now(),
    );
    debugPrint('[transcript:${stage.name}] $message');
    state = state.copyWith(
      stage: stage,
      logs: [...state.logs, entry],
      busy: busy,
      error: error,
      clearError: error == null,
      saved: saved,
    );
  }
}

/// Refreshes the portal when the app returns to the foreground, so a student
/// who reopens the app after class sees current data without pulling.
class PortalLifecycleRefresher extends ConsumerStatefulWidget {
  final Widget child;
  const PortalLifecycleRefresher({super.key, required this.child});

  @override
  ConsumerState<PortalLifecycleRefresher> createState() =>
      _PortalLifecycleRefresherState();
}

class _PortalLifecycleRefresherState
    extends ConsumerState<PortalLifecycleRefresher> with WidgetsBindingObserver {
  DateTime _lastResumeRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Debounce: a quick app-switch shouldn't hammer the portal.
    if (DateTime.now().difference(_lastResumeRefresh) < kAutoRefreshInterval) {
      return;
    }
    _lastResumeRefresh = DateTime.now();
    ref.read(portalProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Watches for a rejected session and bounces the app back to sign-in.
void listenForExpiredSession(WidgetRef ref) {
  ref.listen<AsyncValue<PortalSnapshot>>(portalProvider, (_, next) {
    if (next.hasError && next.error is AuthExpiredException) {
      ref.read(sessionProvider.notifier).markExpired();
    }
  });
}
