import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../data/badge/badge.dart';

const String _confettiAsset = 'assets/lottie/confetti.json';

/// 여러 배지를 순차로 보여준다. 한 번의 amount 기록으로 STREAK + NO_SPEND 가 동시에 들어올 수
/// 있어서 큐 형태 — 동시 표시는 시각적으로 혼란스럽고 모달끼리 겹치면 dismiss 도 깨진다.
Future<void> showBadgeCelebrations(
  BuildContext context,
  List<AcquiredBadge> badges,
) async {
  for (final badge in badges) {
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '배지 획득',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _BadgeCelebrationDialog(badge: badge),
      transitionBuilder: (_, anim, _, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    );
  }
}

class _BadgeCelebrationDialog extends StatefulWidget {
  const _BadgeCelebrationDialog({required this.badge});

  final AcquiredBadge badge;

  @override
  State<_BadgeCelebrationDialog> createState() =>
      _BadgeCelebrationDialogState();
}

class _BadgeCelebrationDialogState extends State<_BadgeCelebrationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _badgeController;
  late final Animation<double> _scale;
  late final Animation<double> _rotate;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _badgeController, curve: Curves.elasticOut),
    );
    // 좌우로 살짝 흔들리는 wobble: -0.06 → +0.06 → 0 (rad ≈ ±3.4°)
    _rotate = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.06), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.06), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.06, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _badgeController, curve: Curves.easeInOut),
    );
    _glow = CurvedAnimation(
      parent: _badgeController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );
    _badgeController.forward();
  }

  @override
  void dispose() {
    _badgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = widget.badge;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 컨페티는 배지 뒤에 깔되, 화면 전체를 덮어 위쪽까지 흩어지게.
            Positioned.fill(
              child: IgnorePointer(
                child: Lottie.asset(
                  _confettiAsset,
                  fit: BoxFit.cover,
                  repeat: false,
                  // 자산이 없거나 디코딩 실패해도 배지 애니메이션은 계속 동작.
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _badgeController,
                    builder: (_, _) {
                      return Transform.rotate(
                        angle: _rotate.value,
                        child: Transform.scale(
                          scale: _scale.value,
                          child: _BadgeWithGlow(
                            badge: badge,
                            glow: _glow.value,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _glow,
                    child: Column(
                      children: [
                        Text(
                          '🎉 배지 획득!',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          badge.label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          badge.type.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          '탭하여 닫기',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeWithGlow extends StatelessWidget {
  const _BadgeWithGlow({required this.badge, required this.glow});

  final AcquiredBadge badge;

  /// 0.0 → 1.0. 글로우 강도 (애니메이션 종반에 최대).
  final double glow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.45 * glow),
            blurRadius: 48 * glow,
            spreadRadius: 12 * glow,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Image.asset(
          badge.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _IconFallback(),
        ),
      ),
    );
  }
}

class _IconFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withValues(alpha: 0.2),
        border: Border.all(color: theme.colorScheme.primary, width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.emoji_events,
        size: 80,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
