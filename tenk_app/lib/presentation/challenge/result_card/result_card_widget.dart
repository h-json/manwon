import 'package:flutter/material.dart';

import '../../../data/amount/amount.dart';
import '../../../data/badge/badge.dart';
import '../../../data/challenge/challenge.dart';
import '../_formatters.dart';

/// 챌린지 결과 카드 위젯. 항상 480x864 (9:16) 고정 크기로 그려져 PNG 캡처/영상 합성에 그대로 들어간다.
///
/// 화면에 띄울 때는 [FittedBox] 로 감싸 디바이스 비율에 맞춰 스케일링한다 — 위젯 자체의 픽셀 좌표는
/// 영상 export 해상도(480x864) 와 1:1 매칭이라 흔들리면 안 된다.
class ResultCardWidget extends StatelessWidget {
  const ResultCardWidget({
    super.key,
    required this.challenge,
    required this.amounts,
    required this.nickname,
  });

  static const double width = 480;
  static const double height = 864;

  final Challenge challenge;
  final List<Amount> amounts;

  /// null 이면 헤더에서 닉네임 부분 생략 — "만원 챌린지" 만 표시.
  final String? nickname;

  bool get _isSuccess => challenge.result == ChallengeResult.success;

  int get _noSpendDays =>
      amounts.where((a) => a.noSpend).map((a) => dateOnly(a.spentDt)).toSet().length;

  int get _diff => challenge.targetAmount - challenge.totalSpent;

  // 성공/실패 색은 캡처가 ThemeData 변동에 영향받지 않도록 hardcode.
  Color get _bgTop => _isSuccess ? const Color(0xFFFFF6CE) : const Color(0xFFF4F4F6);
  Color get _bgBottom => _isSuccess ? const Color(0xFFFFE680) : const Color(0xFFE5E5EA);
  Color get _accent => _isSuccess ? const Color(0xFF5B3F90) : const Color(0xFF4D4D4D);
  Color get _muted =>
      _isSuccess ? const Color(0xFF6B5B3A) : const Color(0xFF6E6E73);

  String get _emoji => _isSuccess ? '🎉' : '💪';
  String get _resultLabel => _isSuccess ? '성공' : '실패';
  String get _resultSub {
    if (_isSuccess) {
      if (_diff > 0) return '${formatWon(_diff)} 아꼈어요';
      return '딱 맞게 썼어요';
    }
    final over = -_diff;
    return '목표보다 ${formatWon(over)} 더 썼어요';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 40, 36, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                nickname: nickname,
                period: formatPeriod(challenge.startDate, challenge.endDate),
                muted: _muted,
                accent: _accent,
              ),
              const SizedBox(height: 36),
              _HeroBlock(
                emoji: _emoji,
                label: _resultLabel,
                sub: _resultSub,
                accent: _accent,
                muted: _muted,
              ),
              const SizedBox(height: 32),
              _StatsCard(
                target: challenge.targetAmount,
                spent: challenge.totalSpent,
                diff: _diff,
                isSuccess: _isSuccess,
                noSpendDays: _noSpendDays,
                accent: _accent,
                muted: _muted,
              ),
              const Spacer(),
              if (challenge.badges.isNotEmpty) ...[
                _BadgeRow(badges: challenge.badges),
                const SizedBox(height: 20),
              ],
              _Footer(accent: _accent, muted: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.nickname,
    required this.period,
    required this.muted,
    required this.accent,
  });

  final String? nickname;
  final String period;
  final Color muted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final title = nickname == null || nickname!.isEmpty
        ? '만원 챌린지'
        : '$nickname님의 만원 챌린지';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          period,
          style: TextStyle(
            fontSize: 13,
            color: muted,
          ),
        ),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({
    required this.emoji,
    required this.label,
    required this.sub,
    required this.accent,
    required this.muted,
  });

  final String emoji;
  final String label;
  final String sub;
  final Color accent;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 96, height: 1.0)),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w800,
            color: accent,
            height: 1.0,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          sub,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.target,
    required this.spent,
    required this.diff,
    required this.isSuccess,
    required this.noSpendDays,
    required this.accent,
    required this.muted,
  });

  final int target;
  final int spent;
  final int diff;
  final bool isSuccess;
  final int noSpendDays;
  final Color accent;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          children: [
            _StatRow(label: '목표', value: formatWon(target), muted: muted, accent: accent),
            const SizedBox(height: 10),
            _StatRow(label: '사용', value: formatWon(spent), muted: muted, accent: accent),
            const SizedBox(height: 12),
            Container(height: 1, color: muted.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            _StatRow(
              label: isSuccess ? '절약' : '초과',
              value: formatWon(diff.abs()),
              muted: muted,
              accent: accent,
              emphasize: true,
              prefix: isSuccess ? '↓' : '↑',
            ),
            if (noSpendDays > 0) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: muted.withValues(alpha: 0.25)),
              const SizedBox(height: 12),
              _StatRow(
                label: '무지출',
                value: '$noSpendDays일',
                muted: muted,
                accent: accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.muted,
    required this.accent,
    this.emphasize = false,
    this.prefix,
  });

  final String label;
  final String value;
  final Color muted;
  final Color accent;
  final bool emphasize;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: emphasize ? 17 : 15,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            color: muted,
          ),
        ),
        Row(
          children: [
            if (prefix != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  prefix!,
                  style: TextStyle(
                    fontSize: emphasize ? 18 : 15,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 22 : 17,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.badges});

  final List<AcquiredBadge> badges;

  @override
  Widget build(BuildContext context) {
    // 너무 많으면 자리 빡빡해지므로 최대 6개까지 + N
    const maxItems = 6;
    final visible = badges.length > maxItems ? badges.take(maxItems).toList() : badges;
    final hidden = badges.length - visible.length;
    return Center(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final b in visible) _StaticBadgeIcon(badge: b),
          if (hidden > 0)
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x33000000),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$hidden',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StaticBadgeIcon extends StatelessWidget {
  const _StaticBadgeIcon({required this.badge});

  final AcquiredBadge badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Image.asset(
        badge.assetPath,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x22000000),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.emoji_events,
            size: 26,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.accent, required this.muted});

  final Color accent;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Tenk',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: accent,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '만원 챌린지',
          style: TextStyle(
            fontSize: 11,
            color: muted,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
