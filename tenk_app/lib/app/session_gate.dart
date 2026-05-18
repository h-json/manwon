import 'package:flutter/material.dart';

import '../presentation/challenge/challenge_list_screen.dart';
import '../presentation/login/login_screen.dart';
import 'scopes.dart';

/// 앱 시작 시 secure storage에 토큰이 있으면 홈으로, 없으면 로그인으로 분기.
///
/// 화면 단위 비동기 로딩 패턴(AsyncStateMixin)을 쓰지 않은 이유: 이 게이트는 분기 1회용이라
/// 에러/재시도 UI가 의미 없고, 결과에 따라 트리 자체가 교체된다. 가장 짧은 코드가 정답.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  Future<bool>? _hasSession;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // initState에선 InheritedWidget을 못 읽는다. didChangeDependencies에서 1회만 시작.
    _hasSession ??= AuthScope.of(context).hasSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == true
            ? const ChallengeListScreen()
            : const LoginScreen();
      },
    );
  }
}
