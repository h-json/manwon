import 'package:flutter/services.dart';
// 카카오 SDK의 `AuthApi`는 우리 [AuthApi]와 이름이 겹치므로 가린다.
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide AuthApi;

import '../api/auth_api.dart';
import 'token_storage.dart';

/// 카카오 SDK 로그인 → 백엔드 JWT 교환 → secure storage 저장 흐름을 한 곳에 모음.
///
/// 정책:
/// - 카카오톡 설치 여부에 따라 `loginWithKakaoTalk` / `loginWithKakaoAccount` 분기.
/// - 백엔드 교환이 끝나면 카카오 SDK가 들고 있는 토큰은 즉시 폐기. 우리는 자체 JWT만 사용한다.
class AuthRepository {
  AuthRepository({required this.api, required this.storage});

  final AuthApi api;
  final TokenStorage storage;

  Future<bool> hasSession() async => (await storage.read()) != null;

  Future<void> loginWithKakao() async {
    final OAuthToken kakaoToken = await _kakaoLogin();
    try {
      final tokens = await api.kakaoLogin(kakaoToken.accessToken);
      await storage.save(tokens);
    } finally {
      // best-effort: 카카오 SDK 측 토큰 폐기. 실패해도 흐름 진행에는 영향 없음.
      try {
        await UserApi.instance.logout();
      } catch (_) {}
    }
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {
      // 백엔드 호출 실패해도 로컬 토큰은 폐기.
    }
    await storage.clear();
  }

  Future<OAuthToken> _kakaoLogin() async {
    final installed = await isKakaoTalkInstalled();
    if (installed) {
      try {
        return await UserApi.instance.loginWithKakaoTalk();
      } catch (e) {
        // 카카오톡 로그인 시 사용자가 카카오톡 진입 직후 취소하면 fallback 으로 계정 로그인.
        if (e is PlatformException && e.code == 'CANCELED') {
          rethrow;
        }
        return UserApi.instance.loginWithKakaoAccount();
      }
    }
    return UserApi.instance.loginWithKakaoAccount();
  }
}
