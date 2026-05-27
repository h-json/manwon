import 'package:flutter/material.dart';
// 카카오 SDK에도 `AuthApi`/`UserApi`가 있어 우리 쪽과 충돌하므로 가린다.
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart'
    hide AuthApi, UserApi;

import 'app/navigator_key.dart';
import 'app/scopes.dart';
import 'app/session_gate.dart';
import 'config/kakao_config.dart';
import 'data/amount/amount_api.dart';
import 'data/api/auth_api.dart';
import 'data/api/dio_client.dart';
import 'data/auth/auth_repository.dart';
import 'data/auth/token_storage.dart';
import 'data/challenge/challenge_api.dart';
import 'data/media/media_api.dart';
import 'data/user/user_api.dart';
import 'presentation/login/login_screen.dart';

/// Composition root.
///
/// 모든 의존성을 여기서 한 번 만들고 InheritedWidget(Scope)으로 트리에 주입한다.
/// 화면이나 서비스는 절대 여기서 직접 import하지 말 것 (Scope를 통해서만 접근).
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
  final challengeApi = ChallengeApi(authDio: dioClient.authDio);
  final amountApi = AmountApi(authDio: dioClient.authDio);
  final mediaApi = MediaApi(authDio: dioClient.authDio);
  final userApi = UserApi(authDio: dioClient.authDio);

  runApp(TenkApp(
    authRepository: authRepository,
    challengeApi: challengeApi,
    amountApi: amountApi,
    mediaApi: mediaApi,
    userApi: userApi,
  ));
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
  const TenkApp({
    super.key,
    required this.authRepository,
    required this.challengeApi,
    required this.amountApi,
    required this.mediaApi,
    required this.userApi,
  });

  final AuthRepository authRepository;
  final ChallengeApi challengeApi;
  final AmountApi amountApi;
  final MediaApi mediaApi;
  final UserApi userApi;

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      repository: authRepository,
      child: ChallengeScope(
        api: challengeApi,
        child: AmountScope(
          api: amountApi,
          child: MediaScope(
            api: mediaApi,
            child: UserScope(
              api: userApi,
              child: MaterialApp(
                title: 'Tenk',
                navigatorKey: navigatorKey,
                theme: ThemeData(
                  colorScheme:
                      ColorScheme.fromSeed(seedColor: const Color(0xFFFEE500)),
                  useMaterial3: true,
                ),
                home: const SessionGate(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
