import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 미리보기 화면이 돌려주는 사용자 액션. null pop 은 "아무것도 안 하고 닫기".
enum VideoPreviewAction { retake, delete }

/// 기존 첨부 영상을 전용 화면에서 재생만 하고 retake/delete 액션을 부모에게 돌려주는 화면.
///
/// 카메라 화면의 녹화 후 미리보기 ([AmountCameraScreen]) 와 같은 레이아웃 — 영상 위, 하단에 두 버튼.
/// 카메라 후 미리보기는 "다시 촬영 / 사용" 인 반면 여기는 "다시 촬영 / 삭제".
/// 실제 카메라 호출·REMOVE 처리는 부모(edit 화면) 책임.
class AmountVideoPreviewScreen extends StatefulWidget {
  const AmountVideoPreviewScreen({super.key, required this.videoPath});

  final String videoPath;

  @override
  State<AmountVideoPreviewScreen> createState() =>
      _AmountVideoPreviewScreenState();
}

class _AmountVideoPreviewScreenState extends State<AmountVideoPreviewScreen> {
  VideoPlayerController? _player;
  Object? _playerError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayerChanged);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.file(File(widget.videoPath));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.play();
      controller.addListener(_onPlayerChanged);
      setState(() => _player = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _playerError = e);
    }
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _togglePlay() async {
    final c = _player;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('영상 미리보기')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(child: _buildPreviewArea(context)),
              const SizedBox(height: 16),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewArea(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_playerError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            const Text(
              '미리보기를 불러올 수 없어요.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _playerError.toString(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final p = _player;
    if (p == null || !p.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: p.value.size.width,
              height: p.value.size.height,
              child: VideoPlayer(p),
            ),
          ),
        ),
        if (!p.value.isPlaying)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 56,
                color: Colors.white,
                icon: const Icon(Icons.play_arrow),
                onPressed: _togglePlay,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context)
                .pop<VideoPreviewAction>(VideoPreviewAction.retake),
            icon: const Icon(Icons.refresh),
            label: const Text('다시 촬영'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context)
                .pop<VideoPreviewAction>(VideoPreviewAction.delete),
            icon: const Icon(Icons.delete_outline),
            label: const Text('삭제'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}
