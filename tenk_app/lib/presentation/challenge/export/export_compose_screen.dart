import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/challenge/challenge.dart';
import '../../../data/export/video_composer.dart';
import 'export_plan.dart';

/// 영상 합본 export 의 3단계 — ffmpeg 로 실제 합성 실행.
///
/// 회의 결정 #11: **전체화면 진행률 + 캔슬 버튼**. 회의 결정 #12 가 prefetch 단계에서 처리되었
/// 으므로 여기서는 ffmpeg 실패 시 동일하게 전체 중단 + 재시도/닫기.
///
/// 종료 시 `Navigator.pop<String>` 으로 결과 파일 경로 반환. 캔슬 또는 실패 시 null.
class ExportComposeScreen extends StatefulWidget {
  const ExportComposeScreen({
    super.key,
    required this.challenge,
    required this.plan,
  });

  final Challenge challenge;
  final ExportPlan plan;

  @override
  State<ExportComposeScreen> createState() => _ExportComposeScreenState();
}

enum _Phase { running, error, cancelled }

class _ExportComposeScreenState extends State<ExportComposeScreen> {
  final VideoComposer _composer = VideoComposer();
  _Phase _phase = _Phase.running;
  ComposeProgress _progress = const ComposeProgress(
    phase: ComposePhase.normalizing,
    currentIndex: 0,
    totalCount: 1,
    message: '준비 중',
  );
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    // 화면 dispose 가 곧 캔슬. 진행 중이던 ffmpeg 세션 정리.
    unawaited(_composer.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.running;
      _errorMessage = null;
      _progress = const ComposeProgress(
        phase: ComposePhase.normalizing,
        currentIndex: 0,
        totalCount: 1,
        message: '준비 중',
      );
    });

    try {
      final tmp = await getTemporaryDirectory();
      final outPath =
          '${tmp.path}/tenk_export/output_${widget.challenge.id}.mp4';
      final result = await _composer.compose(
        plan: widget.plan,
        challengeTargetAmount: widget.challenge.targetAmount,
        challengeStartDate: widget.challenge.startDate,
        outputPath: outPath,
        onPhase: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop<String>(result);
    } on VideoComposeCancelled {
      if (!mounted) return;
      setState(() => _phase = _Phase.cancelled);
    } on VideoComposeFailed catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _retry() {
    _start();
  }

  Future<void> _cancel() async {
    await _composer.cancel();
    if (!mounted) return;
    Navigator.of(context).pop<String>();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope<String?>(
      // 합성 중에는 백 제스처도 캔슬 흐름으로.
      canPop: _phase != _Phase.running,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_cancel());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('영상 합성 중'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: switch (_phase) {
                _Phase.running => _RunningView(
                    progress: _progress,
                    onCancel: _cancel,
                    theme: theme,
                  ),
                _Phase.error => _ErrorView(
                    message: _errorMessage ?? '알 수 없는 오류',
                    onRetry: _retry,
                    onCancel: _cancel,
                    theme: theme,
                  ),
                _Phase.cancelled => _CancelledView(onClose: _cancel),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({
    required this.progress,
    required this.onCancel,
    required this.theme,
  });

  final ComposeProgress progress;
  final VoidCallback onCancel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.movie_filter_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text('영상 만드는 중…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          progress.message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.overall,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress.overall * 100).toStringAsFixed(0)}%',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        TextButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          label: const Text('취소'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onCancel,
    required this.theme,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size: 64,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 20),
        Text('합성에 실패했어요', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onCancel, child: const Text('닫기')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CancelledView extends StatelessWidget {
  const _CancelledView({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cancel_outlined, size: 64),
        const SizedBox(height: 12),
        const Text('취소됨'),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: onClose, child: const Text('닫기')),
      ],
    );
  }
}
