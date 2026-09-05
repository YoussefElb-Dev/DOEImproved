import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../services/transcript/transcript_import_service.dart';
import '../storage/state_providers.dart';
import 'transcript_review_screen.dart';

class TranscriptImportScreen extends ConsumerStatefulWidget {
  const TranscriptImportScreen({super.key});

  @override
  ConsumerState<TranscriptImportScreen> createState() =>
      _TranscriptImportScreenState();
}

class _TranscriptImportScreenState
    extends ConsumerState<TranscriptImportScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(transcriptImportProvider.notifier).reset(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transcriptImportProvider);
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final draft = state.draft?.transcript;

    return Scaffold(
      appBar: AppBar(title: const Text('Import transcript')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          children: [
            SurfaceCard(
              fill: p.accent.withValues(alpha: .08),
              borderColor: p.accent.withValues(alpha: .3),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.upload_file_rounded,
                        size: 32, color: p.accent),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Choose a transcript PDF',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Gradly reads text-layer PDFs on your device. You will '
                    'review and edit every field before anything is saved.',
                    textAlign: TextAlign.center,
                    style: tt.bodySmall?.copyWith(
                      color: p.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => ref
                              .read(transcriptImportProvider.notifier)
                              .pick(),
                      icon: state.busy
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.folder_open_rounded),
                      label: Text(state.busy ? 'Working…' : 'Choose PDF'),
                    ),
                  ),
                ],
              ),
            ),
            if (state.busy) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress(state.stage)),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 14),
              SurfaceCard(
                borderColor: p.danger.withValues(alpha: .6),
                fill: p.danger.withValues(alpha: .07),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, color: p.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(state.error!,
                          style: tt.bodySmall?.copyWith(color: p.danger)),
                    ),
                  ],
                ),
              ),
            ],
            if (draft != null &&
                state.stage == TranscriptImportStage.review) ...[
              const SizedBox(height: 22),
              const SectionLabel('Parse result'),
              const SizedBox(height: 8),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.institution.name ?? 'Institution needs review',
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${draft.terms.length} terms · ${draft.courseCount} courses '
                      '· ${draft.warnings.length} parse notes',
                      style: tt.bodySmall?.copyWith(color: p.textTertiary),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TranscriptReviewScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.fact_check_rounded),
                        label: const Text('Review every field'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (state.logs.isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionLabel('Pipeline log'),
              const SizedBox(height: 8),
              SurfaceCard(
                child: Column(
                  children: [
                    for (final entry in state.logs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              entry.stage == TranscriptImportStage.failed
                                  ? Icons.cancel_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 16,
                              color: entry.stage == TranscriptImportStage.failed
                                  ? p.danger
                                  : p.gradeA,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '${entry.stage.name}: ${entry.message}',
                                style: tt.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _progress(TranscriptImportStage stage) {
    const stages = <TranscriptImportStage>[
      TranscriptImportStage.picker,
      TranscriptImportStage.fileHandle,
      TranscriptImportStage.bytesRead,
      TranscriptImportStage.parse,
      TranscriptImportStage.normalize,
      TranscriptImportStage.validate,
      TranscriptImportStage.review,
      TranscriptImportStage.persist,
      TranscriptImportStage.rerender,
      TranscriptImportStage.complete,
    ];
    final index = stages.indexOf(stage);
    return index < 0 ? 0 : (index + 1) / stages.length;
  }
}
