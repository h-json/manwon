import 'package:dio/dio.dart';

import '../../config/api_config.dart';
import '../auth/token_storage.dart';
import 'auth_interceptor.dart';

/// 두 개의 dio 인스턴스를 묶은 컨테이너.
///
/// - [rawDio]: 인터셉터 없음. 인증 불필요한 `/api/auth/kakao/login`, `/api/auth/refresh`에 사용.
/// - [authDio]: [AuthInterceptor] 부착. 그 외 모든 요청 (`/api/users/me`, `/api/challenges/...` 등)에 사용.
class DioClient {
  DioClient({required this.storage, required this.onLogout}) {
    rawDio = _build();
    authDio = _build();
    AuthInterceptor(
      storage: storage,
      refreshDio: rawDio,
      onLogout: onLogout,
    ).attachTo(authDio);
  }

  final TokenStorage storage;
  final Future<void> Function() onLogout;

  late final Dio rawDio;
  late final Dio authDio;

  static Dio _build() => Dio(
        BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        ),
      );
}
