import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grade_models.dart';
import '../models/schedule_models.dart';
import '../services/auth_webview_service.dart';
import '../services/calculator_service.dart';
import '../services/grade_data_service.dart';
import 'mock_data.dart';
import 'mock_schedule_data.dart';
import 'settings_store.dart';

/// App-wide state providers. Live portal data overrides mock data when
/// a captured session is valid.

final authServiceProvider = Provider<AuthWebViewService>(
  (ref) => AuthWebViewService(),
);

final gradeDataServiceProvider = Provider<GradeDataService>(
  (ref) => GradeDataService(),
);

final calculatorProvider = Provider<CalculatorService>(
  (ref) => const CalculatorService(),
);

/// Restored session cookies (empty = not authenticated).
final sessionCookiesProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.read(authServiceProvider).restoreSession(),
);

final studentProfileProvider = FutureProvider<StudentProfile>((ref) async {
  final cookies = await ref.watch(sessionCookiesProvider.future);
  if (cookies.isNotEmpty) {
    try {
      final live = await ref.read(gradeDataServiceProvider).sync(cookies);
      final p = live.profile;
      if (p != null) return p;
    } on AuthExpiredException {
      // Session invalid — fall through to mock data.
    }
  }
  await Future.delayed(const Duration(milliseconds: 150));
  return mockStudentProfile;
});

final courseListProvider = FutureProvider<List<Course>>((ref) async {
  final cookies = await ref.watch(sessionCookiesProvider.future);
  if (cookies.isNotEmpty) {
    try {
      final live = await ref.read(gradeDataServiceProvider).sync(cookies);
      if (live.courses.isNotEmpty) return live.courses;
    } on AuthExpiredException {
      // fall through to mock data
    }
  }
  await Future.delayed(const Duration(milliseconds: 150));
  return mockCourses;
});

/// Live-sync indicator.
final syncIndicatorProvider = StateNotifierProvider<SyncNotifier, bool>(
  (ref) => SyncNotifier(),
);

/// Schedule from portal — shows "unavailable" card when not posted.
final scheduleProvider = FutureProvider<DaySchedule>((ref) async {
  final cookies = await ref.watch(sessionCookiesProvider.future);
  if (cookies.isNotEmpty) {
    try {
      return await ref.read(gradeDataServiceProvider).fetchSchedule(cookies);
    } on AuthExpiredException {
      // fall through
    }
  }
  await Future.delayed(const Duration(milliseconds: 120));
  return mockDaySchedule;
});

/// Transcript — completed-course records.
final transcriptProvider = FutureProvider<List<TranscriptRecord>>((ref) async {
  final cookies = await ref.watch(sessionCookiesProvider.future);
  if (cookies.isNotEmpty) {
    try {
      final live = await ref.read(gradeDataServiceProvider).fetchTranscript(cookies);
      if (live.isNotEmpty) return live;
    } on AuthExpiredException {
      // fall through
    }
  }
  await Future.delayed(const Duration(milliseconds: 120));
  return mockTranscript;
});

/// Upcoming work items (assignments due).
final workItemsProvider = FutureProvider<List<WorkItem>>((ref) async {
  final cookies = await ref.watch(sessionCookiesProvider.future);
  if (cookies.isNotEmpty) {
    try {
      final live = await ref.read(gradeDataServiceProvider).fetchWork(cookies);
      if (live.isNotEmpty) return live;
    } on AuthExpiredException {
      // fall through
    }
  }
  await Future.delayed(const Duration(milliseconds: 120));
  return mockWorkItems;
});

/// Local profile image path (stored via file picker in Settings).
final profileImageProvider =
    StateNotifierProvider<ProfileImageNotifier, String?>(
  (ref) => ProfileImageNotifier(),
);

class ProfileImageNotifier extends StateNotifier<String?> {
  ProfileImageNotifier() : super(null) {
    SettingsStore.profileImagePath().then((p) {
      if (mounted) state = p;
    });
  }

  Future<void> pick() async {
    final p = await SettingsStore.pickAndSaveProfileImage();
    if (p != null) state = p;
  }

  Future<void> clear() async {
    await SettingsStore.clearProfileImage();
    state = null;
  }
}

class SyncNotifier extends StateNotifier<bool> {
  Timer? _timer;
  SyncNotifier() : super(true) {
    _timer = Timer(const Duration(seconds: 2), () => state = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}