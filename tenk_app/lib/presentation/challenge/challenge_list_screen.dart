import 'package:flutter/material.dart';

import '../../app/scopes.dart';
import '../../data/api/api_error.dart';
import '../../data/challenge/challenge.dart';
import '../common/async_state.dart';
import '../login/login_screen.dart';
import '_formatters.dart';
import 'challenge_create_screen.dart';
import 'challenge_detail_screen.dart';
import 'widgets/challenge_badges.dart';
import 'widgets/challenge_status.dart';

class ChallengeListScreen extends StatefulWidget {
  const ChallengeListScreen({super.key});

  @override
  State<ChallengeListScreen> createState() => _ChallengeListScreenState();
}

class _ChallengeListScreenState extends State<ChallengeListScreen>
    with AsyncStateMixin<ChallengeListScreen, List<Challenge>> {
  bool _loggingOut = false;

  @override
  Future<List<Challenge>> fetch() => ChallengeScope.of(context).list();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ensureLoaded();
  }

  Future<void> _openCreate() async {
    // Navigator generic 추론 문제로 pop result가 누락되는 경우가 있어,
    // result 의존 없이 push 종료 시점에 무조건 새로고침. (handoff.md "함정 — Flutter" 참고)
    await Navigator.of(context).push<Challenge>(
      MaterialPageRoute<Challenge>(
        builder: (_) => const ChallengeCreateScreen(),
      ),
    );
    if (!mounted) return;
    await reload();
  }

  Future<void> _openDetail(Challenge challenge) async {
    // 상세에서 finalize / delete가 일어났을 수 있으니 push 후 무조건 새로고침.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChallengeDetailScreen(challengeId: challenge.id),
      ),
    );
    if (!mounted) return;
    await reload();
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await AuthScope.of(context).logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      final msg = toApiException(e).message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('로그아웃 실패: $msg')));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 챌린지'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: reload,
          child: AsyncStateView<List<Challenge>>(
            data: data,
            error: error,
            loading: loading,
            onRetry: reload,
            builder: (_, challenges) => challenges.isEmpty
                ? const _EmptyView()
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: challenges.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _ChallengeCard(
                      challenge: challenges[i],
                      onTap: () => _openDetail(challenges[i]),
                    ),
                  ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('새 챌린지'),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge, required this.onTap});

  final Challenge challenge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ChallengeStatusChip(challenge: challenge),
                  const Spacer(),
                  Text(
                    formatPeriod(challenge.startDate, challenge.endDate),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('잔액', style: theme.textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Text(
                          formatWon(challenge.balance),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: challenge.balance < 0
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('목표', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 2),
                      Text(
                        formatWon(challenge.targetAmount),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
              if (challenge.badges.isNotEmpty) ...[
                const SizedBox(height: 12),
                ChallengeBadgesRow(
                  badges: challenge.badges,
                  iconSize: 26,
                  maxItems: 5,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '아직 챌린지가 없어요.\n오른쪽 아래 + 버튼으로 첫 챌린지를 시작해보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
