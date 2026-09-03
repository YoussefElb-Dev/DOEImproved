import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grade_models.dart';
import '../models/portal_snapshot.dart';
import '../models/schedule_models.dart';
import '../services/auth_webview_service.dart';
import '../services/calculator_service.dart';
import '../services/grade_data_service.dart';
import '../services/portal_repository.dart';
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

  /// The portal rejected our cookies — drop them so the UI re-authenticates.
  void markExpired() {
    if (state.valueOrNull?.isEmpty ?? false) return;
    state = const AsyncData({});
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).clearSession();
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
    if (cookies.isNotEmpty) {
      _timer = Timer.periodic(kAutoRefreshInterval, (_) => refresh());
    }
    ref.onDispose(() => _timer?.cancel());

    return ref.read(portalRepositoryProvider).load(cookies);
  }

  /// Re-pulls the portal while leaving the current data on screen, so a
  /// refresh never flashes the UI back to skeletons.
  Future<void> refresh() async {
    final cookies = ref.read(sessionProvider).valueOrNull ?? const {};
    state = AsyncValue<PortalSnapshot>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(portalRepositoryProvider).load(cookies),
    );
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

final workItemsProvider = Provider<List<WorkItem>>(
  (ref) => ref.watch(_snapshot.select((s) => s?.openWork)) ?? const [],
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
