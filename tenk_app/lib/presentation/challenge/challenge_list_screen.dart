import 'package:flutter/material.dart';

import '../../data/api/api_error.dart';
import '../../data/challenge/challenge.dart';
import '../../main.dart' show AuthScope, ChallengeScope;
import '../login/login_screen.dart';
import '_formatters.dart';
import 'challenge_create_screen.dart';
import 'challenge_detail_screen.dart';

class ChallengeListScreen extends StatefulWidget {
  const ChallengeListScreen({super.key});

  @override
  State<ChallengeListScreen> createState() => _ChallengeListScreenState();
}

class _ChallengeListScreenState extends State<ChallengeListScreen> {
  List<Challenge>? _challenges;
  Object? _loadError;
  bool _loading = true;
  bool _loggingOut = false;

  /// 같은 화면에서 빠르게 refresh를 두 번 부르면 응답 도착 순서가 뒤집힐 수 있다.
  /// 가장 최근 호출만 state에 반영하기 위한 세대 카운터.
  int _loadGen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadGen == 0) {
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final result = await ChallengeScope.of(context).list();
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _challenges = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _openCreate() async {
    // Navigator generic 추론 문제로 pop result가 누락되는 경우가 있어,
    // result 의존 없이 push 종료 시점에 무조건 새로고침.
    await Navigator.of(context).push<Challenge>(
      MaterialPageRoute<Challenge>(
        builder: (_) => const ChallengeCreateScreen(),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openDetail(Challenge challenge) async {
    // 상세에서 finalize / delete가 일어났을 수 있으니 push 후 무조건 새로고침.
    // (이전엔 result == true일 때만 갱신했는데 누락되는 케이스가 있었다.)
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChallengeDetailScreen(challengeId: challenge.id),
      ),
    );
    if (!mounted) return;
    await _refresh();
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

  Widget _buildBody() {
    if (_loading && _challenges == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _challenges == null) {
      return _ErrorView(
        message: toApiException(_loadError!).message,
        onRetry: _refresh,
      );
    }
    final challenges = _challenges ?? const <Challenge>[];
    if (challenges.isEmpty) {
      return const _EmptyView();
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: challenges.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ChallengeCard(
        challenge: challenges[i],
        onTap: () => _openDetail(challenges[i]),
      ),
    );
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
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
                  _StatusChip(challenge: challenge),
                  const Spacer(),
                  Text(
                    formatPeriod(challenge.startDt, challenge.endDt),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (challenge) {
      Challenge(result: ChallengeResult.success) =>
        ('성공', theme.colorScheme.primary),
      Challenge(result: ChallengeResult.fail) => ('실패', theme.colorScheme.error),
      Challenge(awaitsFinalize: true) => ('결과 확정 대기', theme.colorScheme.tertiary),
      _ => ('진행 중', theme.colorScheme.secondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
