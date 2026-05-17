import 'package:dio/dio.dart';

import '../auth/auth_tokens.dart';
import '../auth/token_storage.dart';

/// 모든 요청에 `Authorization: Bearer <AT>` 부착 + 401 시 `/api/auth/refresh`로 회전 후 1회 재시도.
///
/// 동시 다발 401에 대비해 진행 중인 refresh를 단일 future로 공유한다. refresh 실패 또는
/// `/api/auth/refresh` 자체의 401은 RT가 무효라는 뜻 → 토큰 폐기 + [onLogout] 콜백 호출.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.storage,
    required this.refreshDio,
    required this.onLogout,
  });

  /// refresh 호출에 쓸 raw dio (이 인터셉터가 붙지 않은 인스턴스).
  final Dio refreshDio;
  final TokenStorage storage;
  final Future<void> Function() onLogout;

  /// 이 인터셉터가 부착된 dio. 401 재시도 시 같은 dio로 fetch해 onRequest를 다시 거치게 한다.
  late final Dio _dio;

  Future<bool>? _refreshing;

  static const _retriedKey = 'tenk.auth.retried';

  void attachTo(Dio dio) {
    _dio = dio;
    dio.interceptors.add(this);
  }

  static const _publicPaths = {
    '/api/auth/kakao/login',
    '/api/auth/refresh',
  };

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_publicPaths.contains(options.path)) {
      return handler.next(options);
    }
    final tokens = await storage.read();
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;
    final alreadyRetried = err.requestOptions.extra[_retriedKey] == true;

    if (status != 401) {
      return handler.next(err);
    }
    // refresh 자체가 401이거나 이미 한 번 재시도한 요청이면 더 시도하지 않음.
    if (path == '/api/auth/refresh' || alreadyRetried) {
      await _signOutLocally();
      return handler.next(err);
    }

    final refreshed = await _ensureRefreshed();
    if (!refreshed) {
      await _signOutLocally();
      return handler.next(err);
    }

    final retryOptions = err.requestOptions.copyWith();
    retryOptions.extra[_retriedKey] = true;
    try {
      final response = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _ensureRefreshed() {
    return _refreshing ??=
        _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final tokens = await storage.read();
    if (tokens == null) return false;
    try {
      final res = await refreshDio.post(
        '/api/auth/refresh',
        data: {'refreshToken': tokens.refreshToken},
      );
      final body = res.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      await storage.save(AuthTokens.fromJson(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _signOutLocally() async {
    await storage.clear();
    await onLogout();
  }
}
