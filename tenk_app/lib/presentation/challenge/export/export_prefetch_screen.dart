import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/scopes.dart';
import '../../../data/amount/amount.dart';
import '../../../data/api/api_error.dart';
import 'export_plan.dart';

/// 영상 합본 export 의 2단계 — 선택된 영상들을 디바이스 임시 디렉토리에 다운로드.
///
/// 회의 결정 #12: **1개라도 실패하면 전체 중단 + 재시도 버튼**. 부분 합본을 만들지 않는다.
/// 클립 단위 sequential 다운로드 — 원본이 ResolutionPreset.medium 2초라 파일이 작아
/// 병렬화 이득이 작고, 진행률 표시가 단순해짐.
///
/// 다운로드된 파일들은 `{tmp}/tenk_export/{challengeId}/{fileId}.mp4` 에 저장 — 같은 챌린지 재진입 시
/// 덮어쓴다 (회의 결정 #13 캐싱 안 함과 일치).
///
/// 종료 시 [ExportPlan] 을 `Navigator.pop` 으로 반환. 사용자가 백 / 캔슬 누르면 null 반환.
class ExportPrefetchScreen extends StatefulWidget {
  const ExportPrefetchScreen({
    super.key,
    required this.challengeId,
    required this.items,
  });

  final int challengeId;

  /// 선택된 클립의 입력 모델 — source + 사용자가 편집한 자막.
  /// prefetch 가 끝나면 각 항목에 `localVideoPath` 가 붙어 [ExportPlan] 으로 변환된다.
  final List<ExportPrefetchItem> items;

  @override
  State<ExportPrefetchScreen> createState() => _ExportPrefetchScreenState();
}

/// 입력 항목 — prefetch 화면이 받는 미해결 상태의 클립.
class ExportPrefetchItem {
  const ExportPrefetchItem({required this.source, required this.comment});

  final Amount source;
  final String comment;
}

enum _Phase { downloading, error, cancelled }

class _ExportPrefetchScreenState extends State<ExportPrefetchScreen> {
  _Phase _phase = _Phase.downloading;
  int _doneCount = 0;
  String? _errorMessage;
  CancelToken _cancelToken = CancelToken();

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후 시작 — context 가져오기 안전.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel('screen disposed');
    super.dispose();
  }

  Future<Directory> _ensureDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/tenk_export/${widget.challengeId}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _start() async {
    final mediaApi = MediaScope.of(context);
    final dir = await _ensureDir();
    final results = <ExportClipPlan>[];

    setState(() {
      _phase = _Phase.downloading;
      _doneCount = 0;
      _errorMessage = null;
    });

    try {
      for (final item in widget.items) {
        if (_cancelToken.isCancelled) return;
        final mediaFiles = item.source.mediaFiles;
        String? localPath;
        if (mediaFiles.isNotEmpty) {
          final fileId = mediaFiles.first.fileId;
          localPath = '${dir.path}/$fileId.mp4';
          await mediaApi.downloadToFile(
            fileId: fileId,
            savePath: localPath,
            cancelToken: _cancelToken,
          );
        }
        results.add(ExportClipPlan(
          source: item.source,
          comment: item.comment,
          localVideoPath: localPath,
        ));
        if (!mounted) return;
        setState(() => _doneCount = results.length);
      }

      if (!mounted) return;
      Navigator.of(context).pop<ExportPlan>(ExportPlan(clips: results));
    } catch (e) {
      // dio CancelToken 의 cancel 도 예외로 던진다 — DioException with type=cancel.
      if (e is DioException && CancelToken.isCancel(e)) {
        if (mounted) setState(() => _phase = _Phase.cancelled);
        return;
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = toApiException(e).message;
      });
    }
  }

  void _retry() {
    _cancelToken = CancelToken();
    _start();
  }

  void _cancel() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel('user cancelled');
    Navigator.of(context).pop<ExportPlan>();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.items.length;
    final progress = total == 0 ? 1.0 : (_doneCount / total).clamp(0.0, 1.0);

    return PopScope<ExportPlan?>(
      // 다운로드 중에는 백 제스처도 캔슬 흐름으로 흡수.
      canPop: _phase != _Phase.downloading,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('영상 준비 중'),
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: switch (_phase) {
              _Phase.downloading => _DownloadingView(
                  doneCount: _doneCount,
                  totalCount: total,
                  progress: progress,
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
    );
  }
}

class _DownloadingView extends StatelessWidget {
  const _DownloadingView({
    required this.doneCount,
    required this.totalCount,
    required this.progress,
    required this.onCancel,
    required this.theme,
  });

  final int doneCount;
  final int totalCount;
  final double progress;
  final VoidCallback onCancel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_download_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text('영상을 모으는 중…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '$doneCount / $totalCount',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: totalCount == 0 ? null : progress,
            minHeight: 8,
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
        Text('영상을 가져오지 못했어요', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '하나라도 빠지면 전체가 중단돼요. 잠시 후 다시 시도해주세요.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
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
