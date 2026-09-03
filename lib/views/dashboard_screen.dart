import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/grade_models.dart';
import '../services/calculator_service.dart';
import '../storage/mock_data.dart';
import '../storage/state_providers.dart';
import 'widgets/course_card.dart';
import 'widgets/gpa_hero_card.dart';
import 'widgets/what_if_slider.dart';

/// Main dashboard: floating header bar (brand, avatar, live sync pulse),
/// GPA hero card, and the course feed.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(studentProfileProvider);
    final coursesAsync = ref.watch(courseListProvider);
    final syncing = ref.watch(syncIndicatorProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _TopHeaderBar(
              avatarUrl: profileAsync.valueOrNull?.avatarUrl ?? '',
              syncing: syncing,
            ),
            const SizedBox(height: 20),
            profileAsync.when(
              data: (profile) => GpaHeroCard(profile: profile),
              loading: () => const _LoadingCard(),
              error: (e, _) => _ErrorCard(message: e.toString()),
            ),
            const SizedBox(height: 24),
            Text(
              'YOUR COURSES',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            coursesAsync.when(
              data: (courses) => Column(
                children: [
                  for (final course in courses) ...[
                    CourseCard(
                      course: course,
                      onTap: () => _openCourse(context, course),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
              loading: () => const _LoadingCard(),
              error: (e, _) => _ErrorCard(message: e.toString()),
            ),
          ],
        ),
      ),
    );
  }

  void _openCourse(BuildContext context, Course course) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CourseDetailScreen(course: course),
      ),
    );
  }
}

/// Floating glassmorphism header: brand, avatar, pulsating sync dot.
class _TopHeaderBar extends ConsumerWidget {
  final String avatarUrl;
  final bool syncing;

  const _TopHeaderBar({required this.avatarUrl, required this.syncing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final localImage = ref.watch(profileImageProvider);
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      borderRadius: 20,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _SyncDot(active: syncing),
                const SizedBox(width: 10),
                Text(
                  'DOEImproved',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          _Avatar(avatarUrl: avatarUrl, localImagePath: localImage),
        ],
      ),
    );
  }
}

class _SyncDot extends StatefulWidget {
  final bool active;
  const _SyncDot({required this.active});

  @override
  State<_SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<_SyncDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppColors.gradeA : AppColors.textSecondary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final glow = widget.active ? _c.value : 0.0;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5 * glow),
                blurRadius: 10 * glow + 2,
                spreadRadius: 2 * glow,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final String avatarUrl;
  final String? localImagePath;
  const _Avatar({required this.avatarUrl, this.localImagePath});

  @override
  Widget build(BuildContext context) {
    if (localImagePath != null && localImagePath!.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: FileImage(File(localImagePath!)),
      );
    }
    if (avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(avatarUrl),
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.gradeB.withValues(alpha: 0.2),
      child: const Icon(Icons.person_rounded,
          color: AppColors.gradeB, size: 20),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const GlassContainer(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Text(
        'Failed to load: $message',
        style: TextStyle(color: AppColors.gradeDF),
      ),
    );
  }
}

/// Course detail screen: full assignments and the What-If slider.
class _CourseDetailScreen extends ConsumerWidget {
  final Course course;
  const _CourseDetailScreen({required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final calculator = ref.read(calculatorProvider);
    final gradeColor = AppColors.forLetterGrade(course.letterGrade);

    return Scaffold(
      appBar: AppBar(
        title: Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            GlassContainer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course.teacherName,
                          style: tt.bodyMedium?.copyWith(
                              color: AppColors.textSecondary)),
                      Text(course.code,
                          style: tt.bodySmall
                              ?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  Text(
                    '${course.currentScore.toStringAsFixed(1)}%  ${course.letterGrade}',
                    style: tt.titleLarge?.copyWith(
                      color: gradeColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('CATEGORY BREAKDOWN',
                style: tt.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final cat in course.categories) _CategoryTile(category: cat),
            const SizedBox(height: 24),
            for (final cat in course.categories) ...[
              WhatIfSlider(
                course: course,
                categoryName: cat.name,
                calculator: calculator,
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 10),
            Text('ASSIGNMENTS',
                style: tt.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final a in course.assignments)
              _AssignmentTile(assignment: a),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final GradeCategory category;
  const _CategoryTile({required this.category});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pct = category.categoryScore;
    final color = AppColors.forLetterGrade(
        const CalculatorService().letterGradeFor(pct));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(category.name,
                    style: tt.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text('${pct.toStringAsFixed(1)}%',
                    style: tt.bodyMedium?.copyWith(
                        color: color, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 6,
                backgroundColor: AppColors.surfaceBorder,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'weight ${category.weightPercentage.toStringAsFixed(0)}%',
                style: tt.labelSmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  final Assignment assignment;
  const _AssignmentTile({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = assignment.status == AssignmentStatus.missing
        ? AppColors.gradeDF
        : assignment.status == AssignmentStatus.pending
            ? AppColors.gradeC
            : AppColors.gradeA;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(assignment.title,
                  style: tt.bodyMedium, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              '${assignment.score.toStringAsFixed(0)}/${assignment.maxScore.toStringAsFixed(0)}',
              style: tt.bodyMedium?.copyWith(
                  color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}