import 'package:flutter/material.dart';

import '../../app/scopes.dart';
import '../../data/api/api_error.dart';
import '../../data/challenge/challenge.dart';
import '../common/async_state.dart';
import '_formatters.dart';
import 'widgets/challenge_status.dart';

class ChallengeDetailScreen extends StatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challengeId});

  final int challengeId;

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen>
    with AsyncStateMixin<ChallengeDetailScreen, Challenge> {
  bool _changed = false;
  bool _busy = false;

  @override
  Future<Challenge> fetch() =>
      ChallengeScope.of(context).getOne(widget.challengeId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ensureLoaded();
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
      replaceData(next);
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
          child: AsyncStateView<Challenge>(
            data: data,
            error: error,
            loading: loading,
            onRetry: reload,
            builder: (_, challenge) => _DetailBody(
              challenge: challenge,
              busy: _busy,
              onFinalize: challenge.awaitsFinalize ? _finalize : null,
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
    required this.busy,
    required this.onFinalize,
  });

  final Challenge challenge;
  final bool busy;
  final VoidCallback? onFinalize;

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
          formatPeriod(challenge.startDt, challenge.endDt),
          style: theme.textTheme.titleSmall,
        ),
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
        const SizedBox(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '지출 기록 / 영상 녹화 UI는 다음 단계에서 추가될 예정.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
