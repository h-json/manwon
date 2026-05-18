import 'package:flutter/material.dart';

import '../../../data/challenge/challenge.dart';

/// 챌린지 상태(진행 중 / 결과 확정 대기 / 성공 / 실패)에 따른 라벨·색 매핑.
/// 두 표현(chip, banner)이 공유한다.
({String label, Color color}) _statusOf(BuildContext context, Challenge c) {
  final theme = Theme.of(context);
  return switch (c) {
    Challenge(result: ChallengeResult.success) =>
      (label: '성공', color: theme.colorScheme.primary),
    Challenge(result: ChallengeResult.fail) =>
      (label: '실패', color: theme.colorScheme.error),
    Challenge(awaitsFinalize: true) =>
      (label: '결과 확정 대기', color: theme.colorScheme.tertiary),
    _ => (label: '진행 중', color: theme.colorScheme.secondary),
  };
}

/// 리스트 카드 상단에 박는 컴팩트한 라벨.
class ChallengeStatusChip extends StatelessWidget {
  const ChallengeStatusChip({super.key, required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusOf(context, challenge);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: status.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 상세 화면 상단의 더 큰 배너. 점 표시 + 라벨.
class ChallengeStatusBanner extends StatelessWidget {
  const ChallengeStatusBanner({super.key, required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusOf(context, challenge);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: status.color),
          const SizedBox(width: 8),
          Text(
            status.label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: status.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
