import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_palette.dart';
import '../models/archive_models.dart';
import '../models/grade_models.dart';
import '../models/portal_snapshot.dart';
import '../models/schedule_models.dart';
import '../services/analytics_service.dart';
import '../services/auth_webview_service.dart';
import '../services/document_service.dart';
import '../services/calculator_service.dart';
import '../services/grade_data_service.dart';
import '../services/portal_repository.dart';
import 'archive_store.dart';
import 'settings_store.dart';

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

final transcriptProvider = Provider<List<TranscriptRecord>>(
  (ref) => ref.watch(_snapshot.select((s) => s?.transcript)) ?? const [],
);

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

  Future<void> run() async {
    if (state.isLoading) return;
    state = const AsyncLoading();

    final cookies = _ref.read(sessionProvider).valueOrNull ?? const {};
    final store = _ref.read(archiveStoreProvider);

    state = await AsyncValue.guard(() async {
      final result =
          await _ref.read(documentServiceProvider).sync(cookies, store);

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
      return result;
    });

    _ref.invalidate(archiveReportsProvider);
  }
}

// ─────────────────────────── lifecycle ───────────────────────────

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
