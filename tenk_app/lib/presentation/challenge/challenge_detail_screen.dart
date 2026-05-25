import 'package:flutter/material.dart';

import '../../app/scopes.dart';
import '../../data/amount/amount.dart';
import '../../data/api/api_error.dart';
import '../../data/challenge/challenge.dart';
import '../amount/amount_edit_screen.dart';
import '../amount/amount_record_screen.dart';
import '../common/async_state.dart';
import '_formatters.dart';
import 'export/export_screen.dart';
import 'widgets/badge_celebration_dialog.dart';
import 'widgets/challenge_badges.dart';
import 'widgets/challenge_status.dart';

/// 챌린지 1건 + 그 챌린지의 지출 기록 목록을 함께 다룬다.
/// `AsyncStateMixin`은 단일 자원 가정이라 둘을 record로 묶어 한 번에 fetch한다.
typedef _Detail = ({Challenge challenge, List<Amount> amounts});

class ChallengeDetailScreen extends StatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challengeId});

  final int challengeId;

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen>
    with AsyncStateMixin<ChallengeDetailScreen, _Detail> {
  bool _changed = false;
  bool _busy = false;

  /// 이미 한 번 본 챌린지-배지의 식별자. 새 응답에서 여기 없는 것만 축하 모달로 띄운다.
  /// 첫 로드는 [_baselineSet] 으로 막아 baseline 만 채우고 모달은 띄우지 않는다 —
  /// 화면에 처음 들어왔을 때 과거에 받은 배지를 다시 축하하면 안 됨.
  final Set<int> _knownBadgeIds = <int>{};
  bool _baselineSet = false;

  @override
  Future<_Detail> fetch() async {
    final challengeApi = ChallengeScope.of(context);
    final amountApi = AmountScope.of(context);
    final results = await Future.wait([
      challengeApi.getOne(widget.challengeId),
      amountApi.list(widget.challengeId),
    ]);
    return (
      challenge: results[0] as Challenge,
      amounts: results[1] as List<Amount>,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ensureLoaded();
  }

  /// `reload` 가 끝난 뒤 한 번씩 호출 — baseline 외엔 신규 배지만 골라 축하 모달을 띄운다.
  /// `replaceData` 처럼 mixin 의 reload 를 우회하는 경로에서도 직접 호출할 것.
  Future<void> _syncBadgesAndMaybeCelebrate() async {
    final current = data;
    if (current == null) return;
    final incoming = current.challenge.badges;
    final incomingIds = incoming.map((b) => b.challengeBadgeId).toSet();

    if (!_baselineSet) {
      _knownBadgeIds
        ..clear()
        ..addAll(incomingIds);
      _baselineSet = true;
      return;
    }

    final newBadges = incoming
        .where((b) => !_knownBadgeIds.contains(b.challengeBadgeId))
        .toList()
      ..sort((a, b) => a.acquiredDt.compareTo(b.acquiredDt));

    // 알려진 집합은 모달 띄우기 전에 먼저 갱신해 둔다 —
    // 모달 중 reload 가 또 돌아도 같은 배지를 다시 큐에 넣지 않도록.
    _knownBadgeIds
      ..clear()
      ..addAll(incomingIds);

    if (newBadges.isEmpty || !mounted) return;
    await showBadgeCelebrations(context, newBadges);
  }

  @override
  Future<void> reload() async {
    await super.reload();
    if (!mounted) return;
    await _syncBadgesAndMaybeCelebrate();
  }

  Future<void> _finalize() async {
    setState(() => _busy = true);
    try {
      final next = await ChallengeScope.of(context).finalize(widget.challengeId);
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결과가 확정됐어요.')),
      );
      final current = data;
      if (current != null) {
        replaceData((challenge: next, amounts: current.amounts));
        await _syncBadgesAndMaybeCelebrate();
      } else {
        await reload();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = toApiException(e).message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('확정 실패: $msg')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('챌린지 삭제'),
        content: const Text('이 챌린지와 관련 기록이 삭제돼요. 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ChallengeScope.of(context).delete(widget.challengeId);
      if (!mounted) return;
      Navigator.of(context).pop<bool>(true);
    } catch (e) {
      if (!mounted) return;
      final msg = toApiException(e).message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('삭제 실패: $msg')));
      setState(() => _busy = false);
    }
  }

  void _openExport(Challenge challenge, List<Amount> amounts) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExportScreen(challenge: challenge, amounts: amounts),
      ),
    );
  }

  Future<void> _openRecord(Challenge challenge, {required bool noSpend}) async {
    final result = await Navigator.of(context).push<AmountRecordResult>(
      MaterialPageRoute<AmountRecordResult>(
        builder: (_) => AmountRecordScreen(
          challenge: challenge,
          noSpend: noSpend,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _changed = true;
      if (result.removedNoSpendCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오늘 무지출 기록이 취소되었어요.')),
        );
      }
      await reload();
    }
  }

  Future<void> _openEdit(Challenge challenge, Amount amount) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AmountEditScreen(
          challenge: challenge,
          original: amount,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      _changed = true;
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop<bool>(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('챌린지 상세'),
          actions: [
            IconButton(
              tooltip: '삭제',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: reload,
          child: AsyncStateView<_Detail>(
            data: data,
            error: error,
            loading: loading,
            onRetry: reload,
            builder: (_, detail) => _DetailBody(
              challenge: detail.challenge,
              amounts: detail.amounts,
              busy: _busy,
              onFinalize: detail.challenge.awaitsFinalize ? _finalize : null,
              onRecordSpend: detail.challenge.isInProgress
                  ? () => _openRecord(detail.challenge, noSpend: false)
                  : null,
              onRecordNoSpend: detail.challenge.isInProgress
                  ? () => _openRecord(detail.challenge, noSpend: true)
                  : null,
              onEditAmount: (amount) => _openEdit(detail.challenge, amount),
              onOpenExport: detail.challenge.result != null
                  ? () => _openExport(detail.challenge, detail.amounts)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.challenge,
    required this.amounts,
    required this.busy,
    required this.onFinalize,
    required this.onRecordSpend,
    required this.onRecordNoSpend,
    required this.onEditAmount,
    required this.onOpenExport,
  });

  final Challenge challenge;
  final List<Amount> amounts;
  final bool busy;
  final VoidCallback? onFinalize;
  final VoidCallback? onRecordSpend;
  final VoidCallback? onRecordNoSpend;

  /// 기록 카드 탭 → 수정 화면 진입. 수정 화면 안에서 저장/삭제 양쪽 모두 처리한다.
  final ValueChanged<Amount> onEditAmount;

  /// 챌린지가 확정(SUCCESS/FAIL)된 뒤에만 non-null. 진행 중·시작 전이면 null → 진입 카드 숨김.
  final VoidCallback? onOpenExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = challenge.targetAmount == 0
        ? 0.0
        : (challenge.totalSpent / challenge.targetAmount).clamp(0.0, 1.0);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        ChallengeStatusBanner(challenge: challenge),
        const SizedBox(height: 24),
        Text(
          formatPeriod(challenge.startDate, challenge.endDate),
          style: theme.textTheme.titleSmall,
        ),
        if (challenge.badges.isNotEmpty) ...[
          const SizedBox(height: 16),
          ChallengeBadgesRow(badges: challenge.badges, iconSize: 36),
        ],
        const SizedBox(height: 24),
        Text('잔액', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          formatWon(challenge.balance),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: challenge.balance < 0
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: progress >= 1.0
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('누적 지출 ${formatWon(challenge.totalSpent)}',
                style: theme.textTheme.bodyMedium),
            Text('목표 ${formatWon(challenge.targetAmount)}',
                style: theme.textTheme.bodyMedium),
          ],
        ),
        if (onFinalize != null) ...[
          const SizedBox(height: 32),
          FilledButton(
            onPressed: busy ? null : onFinalize,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('결과 확정하기'),
          ),
          const SizedBox(height: 8),
          Text(
            '챌린지가 종료됐어요. 결과를 확정해서 배지를 받을 수 있어요.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (challenge.isBeforeStart) ...[
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '아직 시작하지 않은 챌린지예요.\n시작일(${formatDate(challenge.startDate)})부터 기록할 수 있어요.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        if (challenge.isInProgress) ...[
          const SizedBox(height: 32),
          _TodayActionPanel(
            amounts: amounts,
            busy: busy,
            onRecordSpend: onRecordSpend,
            onRecordNoSpend: onRecordNoSpend,
          ),
        ],
        if (onOpenExport != null) ...[
          const SizedBox(height: 32),
          _ExportEntryCard(onTap: busy ? null : onOpenExport),
        ],
        const SizedBox(height: 32),
        Text('기록 (${amounts.length})', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (amounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '아직 기록이 없어요.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._buildGroupedAmounts(amounts, onEditAmount),
      ],
    );
  }

  /// 백엔드는 spentDt asc 로 보내지만 화면은 "최신이 위" 가 자연스러움 → 그룹 자체도, 그룹 안에서도 내림차순.
  /// 같은 날에 무지출과 지출이 섞이는 케이스는 백엔드 자동 취소 로직이 막아주지만 (`AmountService.record`),
  /// 방어적으로 헤더는 "지출이 있으면 합계 / 없고 무지출만 있으면 '무지출'" 로 표기.
  List<Widget> _buildGroupedAmounts(
    List<Amount> all,
    ValueChanged<Amount> onEdit,
  ) {
    final byDay = <DateTime, List<Amount>>{};
    for (final a in all) {
      byDay.putIfAbsent(dateOnly(a.spentDt), () => []).add(a);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    final widgets = <Widget>[];
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final dayAmounts = byDay[day]!
        ..sort((a, b) => b.spentDt.compareTo(a.spentDt));
      final spendTotal = dayAmounts
          .where((a) => !a.noSpend)
          .fold<int>(0, (sum, a) => sum + a.amount);
      final isNoSpendDay = spendTotal == 0 && dayAmounts.any((a) => a.noSpend);

      if (i > 0) widgets.add(const SizedBox(height: 16));
      widgets.add(_DaySectionHeader(
        day: day,
        isNoSpend: isNoSpendDay,
        spendTotal: spendTotal,
      ));
      widgets.add(const SizedBox(height: 4));
      for (final a in dayAmounts) {
        widgets.add(_AmountTile(
          amount: a,
          onTap: () => onEdit(a),
        ));
      }
    }
    return widgets;
  }
}

/// 진행 중 챌린지에서 "오늘 어떤 행동을 할 수 있나" 를 좌우하는 패널.
///
/// 분기 3가지:
/// 1. 오늘 무지출 기록이 있음 → 강조 카드만, 두 버튼 모두 숨김 (오늘은 절약을 의지로 박았으니
///    지출 진입점을 보여주지 않음. 마음 바꾸려면 아래 무지출 row 삭제).
/// 2. 오늘 지출 기록이 1건 이상 → 오늘 지출 합계 카드 + 지출 버튼만 (무지출은 이미 의미 없음).
/// 3. 오늘 기록 없음 → 지출/무지출 두 버튼 다.
class _TodayActionPanel extends StatelessWidget {
  const _TodayActionPanel({
    required this.amounts,
    required this.busy,
    required this.onRecordSpend,
    required this.onRecordNoSpend,
  });

  final List<Amount> amounts;
  final bool busy;
  final VoidCallback? onRecordSpend;
  final VoidCallback? onRecordNoSpend;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final todayAmounts =
        amounts.where((a) => dateOnly(a.spentDt) == today).toList();
    final hasNoSpendToday = todayAmounts.any((a) => a.noSpend);
    final spendToday =
        todayAmounts.where((a) => !a.noSpend).toList(growable: false);
    final hasSpendToday = spendToday.isNotEmpty;
    final spendTodayTotal =
        spendToday.fold<int>(0, (sum, a) => sum + a.amount);

    if (hasNoSpendToday) {
      // 이번 챌린지 안의 누적 무지출 일수 — 백엔드 자동 취소 로직이 있어 noSpend row 의 DISTINCT day
      // 만 세면 백엔드 정의(`BadgeGrantService.daysWithOnlyNoSpend`)와 동일하다.
      final noSpendDays = amounts
          .where((a) => a.noSpend)
          .map((a) => dateOnly(a.spentDt))
          .toSet()
          .length;
      return _NoSpendTodayCard(noSpendDays: noSpendDays);
    }
    if (hasSpendToday) {
      return Column(
        children: [
          _TodaySpendSummaryCard(total: spendTodayTotal),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : onRecordSpend,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('지출 기록'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : onRecordSpend,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('지출 기록'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: busy ? null : onRecordNoSpend,
            icon: const Icon(Icons.do_not_disturb_on_outlined),
            label: const Text('무지출'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoSpendTodayCard extends StatelessWidget {
  const _NoSpendTodayCard({required this.noSpendDays});

  /// 이 챌린지 안의 누적 무지출 일수. NO_SPEND 배지의 사다리(3/7/14/30) 와 동일한 정의.
  final int noSpendDays;

  /// 백엔드 `BadgeType.NO_SPEND` 의 condition_value 와 일치. 사다리는 [docs/schema.sql](docs/schema.sql)
  /// badge 마스터 시드와 1:1 매칭되며, 변경 시 양쪽을 같이 갱신할 것.
  static const _ladder = [3, 7, 14, 30];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextStep = _ladder.firstWhere(
      (s) => s > noSpendDays,
      orElse: () => _ladder.last,
    );
    final reachedMax = noSpendDays >= _ladder.last;
    final goal = reachedMax ? _ladder.last : nextStep;
    final progress = (noSpendDays / goal).clamp(0.0, 1.0);
    final daysToGo = (nextStep - noSpendDays).clamp(0, _ladder.last);

    return Card(
      color: theme.colorScheme.secondaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          children: [
            Icon(
              Icons.emoji_events,
              size: 56,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(height: 12),
            Text(
              '오늘은 무지출!',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              reachedMax
                  ? '챌린지 풀 무지출 $noSpendDays일 달성!'
                  : '이번 챌린지 무지출 $noSpendDays일째 누적 중',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                color: theme.colorScheme.onSecondaryContainer,
                backgroundColor: theme.colorScheme.onSecondaryContainer
                    .withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$noSpendDays / $goal일',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  reachedMax
                      ? '최고 단계 달성 🎉'
                      : '다음 배지까지 $daysToGo일',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 확정된 챌린지에서만 노출되는 영상 합본 진입 카드. 회의 결정 #2 (노출 시점 = 확정 후) 와 일치.
class _ExportEntryCard extends StatelessWidget {
  const _ExportEntryCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          child: Row(
            children: [
              Icon(
                Icons.movie_creation_outlined,
                size: 36,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '영상 만들기',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '기록 영상을 시간순으로 합쳐 하나의 영상으로.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodaySpendSummaryCard extends StatelessWidget {
  const _TodaySpendSummaryCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.today,
                color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '오늘 ${formatWon(total)} 지출했어요',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySectionHeader extends StatelessWidget {
  const _DaySectionHeader({
    required this.day,
    required this.isNoSpend,
    required this.spendTotal,
  });

  final DateTime day;
  final bool isNoSpend;
  final int spendTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            formatDayHeader(day),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            isNoSpend ? '무지출' : formatWon(spendTotal),
            style: theme.textTheme.titleSmall?.copyWith(
              color: isNoSpend
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({required this.amount, required this.onTap});

  final Amount amount;

  /// 탭 → 수정 화면 진입. 삭제도 수정 화면 안에서만 가능 (별도 X 버튼 없음).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasVideo = amount.mediaFiles.isNotEmpty;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: amount.noSpend
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.primaryContainer,
          child: Icon(
            amount.noSpend
                ? Icons.do_not_disturb_on_outlined
                : Icons.payments_outlined,
            color: amount.noSpend
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          amount.noSpend ? '무지출' : '${amount.category ?? ''} · ${amount.content ?? ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(formatDateTime(amount.spentDt)),
            if (hasVideo) ...[
              const SizedBox(width: 8),
              Icon(Icons.videocam_outlined,
                  size: 14, color: theme.colorScheme.outline),
            ],
          ],
        ),
        trailing: !amount.noSpend
            ? Text(
                formatWon(amount.amount),
                style: theme.textTheme.titleSmall,
              )
            : null,
      ),
    );
  }
}
