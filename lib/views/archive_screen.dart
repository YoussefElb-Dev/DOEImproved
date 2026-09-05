import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/archive_models.dart';
import '../services/document_service.dart';
import '../storage/archive_store.dart';
import '../storage/state_providers.dart';
import 'document_viewer_screen.dart';
import 'documents_browser_screen.dart';
import 'transcript_library_screen.dart';

/// Everything the app has kept: the DOE's own PDFs, and a dated record of the
/// grades as they stood each day.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final reports = ref.watch(archiveReportsProvider);
    final documents = ref.watch(savedDocumentsProvider);
    final usage = ref.watch(storageUsageProvider);
    final sync = ref.watch(documentSyncProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved history')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
          children: [
            Text(
              'The DOE clears old grades when a marking period ends. Gradly '
              'keeps a copy on this device so you can still look back.',
              style: tt.bodySmall?.copyWith(color: p.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 18),

            SurfaceCard(
              child: Row(
                children: [
                  Icon(Icons.sd_storage_rounded, size: 20, color: p.textSecondary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('On this device',
                            style: tt.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          usage.when(
                            data: ArchiveStore.formatBytes,
                            loading: () => 'Measuring…',
                            error: (_, __) => 'Unknown',
                          ),
                          style: tt.bodySmall?.copyWith(color: p.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _confirmClear(context, ref),
                    child: Text('Delete all',
                        style: TextStyle(color: p.danger)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            const SectionLabel('Transcript library'),
            const SizedBox(height: 8),
            SurfaceCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TranscriptLibraryScreen(),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.school_rounded, color: p.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Parsed transcripts',
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Import, review, compare GPA and export your records',
                          style: tt.bodySmall?.copyWith(color: p.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: 22),

            const SectionLabel('DOE documents'),
            const SizedBox(height: 6),
            Text(
              'Transcripts and report cards, downloaded and saved as the '
              'original PDF.',
              style: tt.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 10),
            _DownloadCard(state: sync),
            const SizedBox(height: 10),
            documents.when(
              loading: () => const SkeletonCard(lines: 2),
              error: (e, __) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not read saved documents',
                message: '$e',
              ),
              data: (docs) => docs.isEmpty
                  ? const EmptyState(
                      icon: Icons.picture_as_pdf_outlined,
                      title: 'No documents yet',
                      message:
                          'Download them from the DOE and they will be kept here.',
                    )
                  : Column(
                      children: [
                        for (final (i, doc) in docs.indexed) ...[
                          FadeSlideIn(index: i, child: _DocumentRow(document: doc)),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 24),

            const SectionLabel('Saved reports'),
            const SizedBox(height: 6),
            Text(
              'One per day the app synced, with the grades exactly as they '
              'were then.',
              style: tt.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 10),
            reports.when(
              loading: () => const SkeletonCard(lines: 3),
              error: (e, __) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not read the archive',
                message: '$e',
              ),
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'Nothing saved yet',
                      message:
                          'A report is kept each day the app syncs with the portal.',
                    )
                  : Column(
                      children: [
                        for (final (i, meta) in list.indexed) ...[
                          FadeSlideIn(
                            index: i,
                            child: _ReportRow(meta: meta),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final p = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete saved history?'),
        content: const Text(
          'This removes every saved report and document from this device. '
          'The DOE may no longer have the older ones, so this cannot be '
          'undone by syncing again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: p.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(archiveStoreProvider).clearAll();
    ref
      ..invalidate(archiveReportsProvider)
      ..invalidate(savedDocumentsProvider)
      ..invalidate(storageUsageProvider);
  }
}

/// The button that pulls documents from the DOE, plus whatever it last said.
class _DownloadCard extends ConsumerWidget {
  final AsyncValue<DocumentSyncResult?> state;

  const _DownloadCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final busy = state.isLoading;

    String? message;
    var messageColour = p.textSecondary;
    final result = state.valueOrNull;
    if (state.hasError) {
      message = '${state.error}';
      messageColour = p.danger;
    } else if (result != null) {
      if (result.failure != null) {
        message = result.needsSignIn
            ? 'The DOE document site has its own sign-in. Tap Open and log in '
                'there — it will not affect your gradebook session.'
            : result.failure;
        messageColour = p.warning;
      } else {
        final parts = [
          'Saved ${result.saved.length} '
              '${result.saved.length == 1 ? 'document' : 'documents'}',
          if (result.transcript.isNotEmpty)
            'read ${result.transcript.length} transcript rows',
          if (result.normalizedTranscripts.isNotEmpty)
            'added ${result.normalizedTranscripts.fold<int>(
              0,
              (sum, record) => sum + record.courseCount,
            )} taken classes to Grades',
        ];
        message = '${parts.join(' and ')}.';
        messageColour = p.gradeA;
      }
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_download_rounded, size: 20, color: p.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Get them from the DOE',
                      style:
                          tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Opens the DOE page. Tap a document there and Gradly '
                      'keeps a copy.',
                      style: tt.bodySmall?.copyWith(color: p.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: busy ? null : () => openDocuments(context, ref),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Open'),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: tt.bodySmall?.copyWith(color: messageColour, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final SavedDocument document;

  const _DocumentRow({required this.document});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DocumentViewerScreen(document: document),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf_rounded, size: 20, color: p.danger),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${document.kind} · ${ArchiveStore.formatBytes(document.bytes)}'
                  ' · saved ${shortDate(document.savedAt)}',
                  style: tt.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          if (!document.textExtracted)
            Tooltip(
              message: 'Saved, but its text could not be read',
              child: Icon(Icons.info_outline_rounded,
                  size: 17, color: p.textTertiary),
            ),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.textTertiary),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final ArchivedReportMeta meta;

  const _ReportRow({required this.meta});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArchivedReportScreen(id: meta.id),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortDate(meta.capturedAt),
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (meta.term.isNotEmpty) meta.term,
                    '${meta.courseCount} courses',
                    if (meta.transcriptCount > 0)
                      '${meta.transcriptCount} on transcript',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          if (meta.gpa > 0)
            Text(
              meta.gpa.toStringAsFixed(2),
              style: tt.titleSmall?.copyWith(
                color: p.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.textTertiary),
        ],
      ),
    );
  }
}

/// One saved day, exactly as the portal showed it then.
class ArchivedReportScreen extends ConsumerWidget {
  final String id;

  const ArchivedReportScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final report = ref.watch(archivedReportProvider(id));

    return Scaffold(
      appBar: AppBar(title: Text(id)),
      body: SafeArea(
        child: report.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => Center(child: Text('$e')),
          data: (data) {
            if (data == null) {
              return const Center(child: Text('This report is no longer saved.'));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
              children: [
                SurfaceCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'GPA then',
                          value: data.gpa > 0
                              ? data.gpa.toStringAsFixed(2)
                              : '—',
                          valueColor: p.accent,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Credits',
                          value: data.credits > 0
                              ? data.credits.toStringAsFixed(1)
                              : '—',
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Term',
                          value: data.term.isEmpty ? '—' : data.term,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (data.courses.isNotEmpty) ...[
                  const SectionLabel('Courses'),
                  const SizedBox(height: 10),
                  for (final course in data.courses) ...[
                    _FrozenRow(
                      title: course.title,
                      subtitle: [
                        if (course.code.isNotEmpty) course.code,
                        if (course.teacherName.isNotEmpty) course.teacherName,
                      ].join('  ·  '),
                      mark: course.letterGrade,
                      score: course.currentScore,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                if (data.transcript.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const SectionLabel('Transcript'),
                  const SizedBox(height: 10),
                  for (final record in data.transcript) ...[
                    _FrozenRow(
                      title: record.courseTitle,
                      subtitle: [
                        if (record.courseCode.isNotEmpty) record.courseCode,
                        if (record.term.isNotEmpty) record.term,
                        '${record.creditsEarned.toStringAsFixed(1)} cr',
                      ].join('  ·  '),
                      mark: record.letterGrade,
                      score: record.finalScore,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                const SizedBox(height: 18),
                Text(
                  'Saved ${shortDate(data.capturedAt)} at '
                  '${clockTime(data.capturedAt)}.',
                  style: tt.labelSmall?.copyWith(color: p.textTertiary),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FrozenRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String mark;
  final double score;

  const _FrozenRow({
    required this.title,
    required this.subtitle,
    required this.mark,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final colour = mark.isEmpty ? p.forScore(score) : p.forLetter(mark);

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (score > 0)
            Text(
              '${score.toStringAsFixed(0)}%',
              style: tt.labelMedium?.copyWith(color: p.textSecondary),
            ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colour.withValues(alpha: 0.3)),
            ),
            child: Text(
              mark.isEmpty ? '—' : mark,
              textAlign: TextAlign.center,
              style: tt.labelMedium?.copyWith(
                color: colour,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Opens the DOE document site, then saves whatever was found there.
///
/// The page builds its document list in JavaScript, so the list cannot be read
/// over plain HTTP — the browser screen loads the real page, finds the links
/// in the rendered DOM, and catches any download the student taps.
///
/// Cookies captured there are merged into the session rather than replacing
/// it, so this never costs the gradebook login.
Future<void> openDocuments(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final result = await navigator.push<DocumentsBrowserResult>(
    MaterialPageRoute<DocumentsBrowserResult>(
      builder: (_) => const DocumentsBrowserScreen(),
    ),
  );
  if (result == null) return;

  if (result.cookies.isNotEmpty) {
    await ref.read(sessionProvider.notifier).addCookies(result.cookies);
  }
  if (result.links.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Nothing was captured. Tap a document on the page.'),
      ),
    );
    return;
  }
  await ref.read(documentSyncProvider.notifier).saveFound(result.links);
}
