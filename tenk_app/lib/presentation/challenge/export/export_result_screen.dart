import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

/// 영상 합본 export 의 마지막 단계 — 결과 영상 미리보기 + 갤러리 저장 + OS 공유.
///
/// 회의 결정 #14: **미리보기 + 갤러리 저장 + OS 공유 시트 세 가지 모두** 노출. 사용자가 선택.
/// 결과 영상 자체는 임시 디렉토리에 있고 (회의 결정 #13 캐싱 X — 다음번 export 시 덮어쓰기 예정),
/// 영구 보관은 갤러리 저장이 책임.
class ExportResultScreen extends StatefulWidget {
  const ExportResultScreen({super.key, required this.videoPath});

  /// 합성된 영상 파일의 절대 경로.
  final String videoPath;

  @override
  State<ExportResultScreen> createState() => _ExportResultScreenState();
}

class _ExportResultScreenState extends State<ExportResultScreen> {
  VideoPlayerController? _controller;
  Object? _playerError;
  bool _savedToGallery = false;
  bool _saving = false;
  bool _sharing = false;
  int? _fileSizeBytes;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final file = File(widget.videoPath);
      _fileSizeBytes = await file.length();
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _playerError = e);
    }
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
  }

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // gal: API 30+ 는 MediaStore, 이하만 WRITE_EXTERNAL_STORAGE 필요 (Android Manifest 에 명시).
      // iOS 는 NSPhotoLibraryAddUsageDescription 첫 호출 시 시스템 dialog.
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: false);
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('갤러리 접근 권한이 거부됐어요. 설정에서 사진 접근을 허용해주세요.'),
            ),
          );
          return;
        }
      }
      await Gal.putVideo(widget.videoPath, album: 'Tenk');
      if (!mounted) return;
      setState(() => _savedToGallery = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('갤러리에 저장됐어요.')),
      );
    } on GalException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_galErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final params = ShareParams(
        files: [XFile(widget.videoPath, mimeType: 'video/mp4')],
        text: '만원 챌린지 결과 영상',
      );
      await SharePlus.instance.share(params);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static String _galErrorMessage(GalException e) {
    return switch (e.type) {
      GalExceptionType.accessDenied =>
        '갤러리 접근 권한이 거부됐어요. 설정에서 사진 접근을 허용해주세요.',
      GalExceptionType.notEnoughSpace => '저장 공간이 부족해요.',
      GalExceptionType.notSupportedFormat => '지원하지 않는 영상 형식이에요.',
      GalExceptionType.unexpected => '알 수 없는 오류가 발생했어요.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('완성된 영상')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(child: _buildPreview(theme)),
              ),
              const SizedBox(height: 12),
              _Metadata(
                fileSizeBytes: _fileSizeBytes,
                duration: _controller?.value.duration,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _saving ? null : _saveToGallery,
                      icon: Icon(_savedToGallery
                          ? Icons.check
                          : Icons.download_outlined),
                      label: Text(
                        _saving
                            ? '저장 중…'
                            : _savedToGallery
                                ? '저장됨'
                                : '갤러리 저장',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : _share,
                      icon: const Icon(Icons.ios_share),
                      label: Text(_sharing ? '공유 중…' : '공유하기'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (_playerError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              '미리보기를 불러올 수 없어요.\n파일은 만들어졌으니 저장/공유는 가능해요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return AspectRatio(
      aspectRatio: c.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: VideoPlayer(c),
          ),
          if (!c.value.isPlaying)
            DecoratedBox(
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
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: theme.colorScheme.primary,
                bufferedColor: Colors.white.withValues(alpha: 0.4),
                backgroundColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.fileSizeBytes, required this.duration});

  final int? fileSizeBytes;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];
    if (duration != null) {
      final secs = duration!.inMilliseconds / 1000.0;
      parts.add('${secs.toStringAsFixed(1)}초');
    }
    if (fileSizeBytes != null) {
      parts.add(_formatBytes(fileSizeBytes!));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)}KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
}
