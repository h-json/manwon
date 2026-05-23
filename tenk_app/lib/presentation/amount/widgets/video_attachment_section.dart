import 'package:flutter/material.dart';

/// 영상 첨부 상태를 보여주고 행동 버튼만 노출하는 공용 위젯.
///
/// 상태 분기:
/// - 영상 없음: "촬영하기" 버튼만
/// - 영상 있음 (새로 찍은 로컬 path 또는 기존 서버 영상): "다시 촬영" + "삭제" 버튼
///
/// 카메라 화면 전이/임시 파일 정리는 부모(record/edit 화면)가 책임진다.
/// 이 위젯은 단순히 콜백 호출만 한다.
class VideoAttachmentSection extends StatelessWidget {
  const VideoAttachmentSection({
    super.key,
    required this.hasVideo,
    required this.fromServer,
    required this.onPickNew,
    required this.onRemove,
  });

  /// 영상이 첨부된 상태인지. 로컬 path 든 서버 영상이든 동일하게 "있음" 으로 처리.
  final bool hasVideo;

  /// 기존 서버 영상인지 여부. 메시지를 살짝 다르게 보여주기 위해서만 사용.
  final bool fromServer;

  /// "촬영하기" / "다시 촬영" 트리거.
  final VoidCallback onPickNew;

  /// "삭제" 트리거. 영상 없음 상태에서는 호출되지 않는다.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: hasVideo ? _buildAttached(context) : _buildEmpty(context),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.videocam_off_outlined, color: theme.colorScheme.outline),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '첨부된 영상이 없어요.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onPickNew,
          icon: const Icon(Icons.videocam),
          label: const Text('촬영하기'),
        ),
      ],
    );
  }

  Widget _buildAttached(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fromServer ? '기존 영상이 첨부돼 있어요.' : '2초 영상 녹화 완료',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: onPickNew,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 촬영'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('삭제'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
