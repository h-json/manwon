import 'package:dio/dio.dart';

import '../auth/auth_tokens.dart';
import 'api_response.dart';

/// 백엔드 `/api/auth/*` 엔드포인트 호출.
///
/// - `kakaoLogin`: 카카오 access token을 자체 JWT로 교환. 인증 불필요 → [_rawDio] 사용.
/// - `logout`: 현재 사용자의 모든 RT를 무효화. 인증 필요 → [_authDio] 사용.
///
/// `/api/auth/refresh`는 [AuthInterceptor] 내부에서만 직접 호출하므로 여기엔 노출 안 함.
class AuthApi {
  AuthApi({required Dio rawDio, required Dio authDio})
      : _rawDio = rawDio,
        _authDio = authDio;

  final Dio _rawDio;
  final Dio _authDio;

  Future<AuthTokens> kakaoLogin(String kakaoAccessToken) async {
    final res = await _rawDio.post(
      '/api/auth/kakao/login',
      data: {'accessToken': kakaoAccessToken},
    );
    return AuthTokens.fromJson(unwrapData(res.data));
  }

  Future<void> logout() async {
    await _authDio.post('/api/auth/logout');
  }
}
