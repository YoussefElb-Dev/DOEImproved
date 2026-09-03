import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/grade_controllers.dart';
import '../models/grade_models.dart';
import '../services/auth_webview_service.dart';
import '../services/calculator_service.dart';
import '../services/grade_data_service.dart';
import 'mock_data.dart';

/// App-wide state providers. Live SS data overrides mock data when
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
      if (live.profile != null) return live.profile;
    } on AuthExpiredException {
      ref.read(sessionCookiesProvider.notifier).state = const AsyncData({});
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

/// Simulated live-sync indicator.
final syncIndicatorProvider = StateNotifierProvider<SyncNotifier, bool>(
  (ref) => SyncNotifier(),
);

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