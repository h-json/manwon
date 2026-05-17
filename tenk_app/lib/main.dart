import 'package:flutter/material.dart';
// 카카오 SDK에도 `AuthApi`가 있어 우리 쪽 [AuthApi]와 충돌하므로 가린다.
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide AuthApi;

import 'config/kakao_config.dart';
import 'data/api/auth_api.dart';
import 'data/api/dio_client.dart';
import 'data/auth/auth_repository.dart';
import 'data/auth/token_storage.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/login/login_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);

  final storage = TokenStorage();
  final dioClient = DioClient(
    storage: storage,
    onLogout: () async => _goToLogin(),
  );
  final authApi = AuthApi(rawDio: dioClient.rawDio, authDio: dioClient.authDio);
  final authRepository = AuthRepository(api: authApi, storage: storage);

  runApp(TenkApp(authRepository: authRepository));
}

Future<void> _goToLogin() async {
  final navigator = navigatorKey.currentState;
  if (navigator == null) return;
  await navigator.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

class TenkApp extends StatelessWidget {
  const TenkApp({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      repository: authRepository,
      child: MaterialApp(
        title: 'Tenk',
        navigatorKey: navigatorKey,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFEE500)),
          useMaterial3: true,
        ),
        home: const _SessionGate(),
      ),
    );
  }
}

/// 앱 시작 시 secure storage에 토큰이 있으면 홈으로, 없으면 로그인으로 분기.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
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
        return snapshot.data == true ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}

/// 트리 어디서든 [AuthRepository]를 꺼내쓰기 위한 단순 InheritedWidget.
class AuthScope extends InheritedWidget {
  const AuthScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final AuthRepository repository;

  static AuthRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope not found in widget tree');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(AuthScope oldWidget) =>
      repository != oldWidget.repository;
}
