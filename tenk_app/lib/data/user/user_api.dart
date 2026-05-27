import 'package:dio/dio.dart';

import '../api/api_response.dart';
import 'user.dart';

/// 백엔드 `/api/users/*` 엔드포인트. 결과 카드의 닉네임 표시 등에 사용.
class UserApi {
  UserApi({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  Future<User> getMe() async {
    final res = await _dio.get('/api/users/me');
    return User.fromJson(unwrapData(res.data));
  }
}
