import 'package:dio/dio.dart';

import '../api/api_response.dart';
import 'challenge.dart';

/// 백엔드 `/api/challenges/*` 호출. 모두 인증 필요 → [_dio]는 인터셉터가 부착된 authDio.
class ChallengeApi {
  ChallengeApi({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  Future<Challenge> create({
    required DateTime startDt,
    required DateTime endDt,
    required int targetAmount,
  }) async {
    final res = await _dio.post(
      '/api/challenges',
      data: {
        'startDt': _formatLocal(startDt),
        'endDt': _formatLocal(endDt),
        'targetAmount': targetAmount,
      },
    );
    return Challenge.fromJson(unwrapData(res.data));
  }

  Future<List<Challenge>> list({bool activeOnly = false}) async {
    final res = await _dio.get(
      '/api/challenges',
      queryParameters: {'activeOnly': activeOnly},
    );
    return unwrapList(res.data)
        .map(Challenge.fromJson)
        .toList(growable: false);
  }

  Future<Challenge> getOne(int challengeId) async {
    final res = await _dio.get('/api/challenges/$challengeId');
    return Challenge.fromJson(unwrapData(res.data));
  }

  Future<Challenge> finalize(int challengeId) async {
    final res = await _dio.post('/api/challenges/$challengeId/finalize');
    return Challenge.fromJson(unwrapData(res.data));
  }

  Future<void> delete(int challengeId) async {
    await _dio.delete('/api/challenges/$challengeId');
  }

  /// 백엔드의 LocalDateTime은 타임존 없는 ISO-8601 string을 기대한다.
  /// `DateTime.toIso8601String()`은 로컬/UTC 여부에 따라 'Z'를 붙일 수 있어 LocalDateTime 파서가 깨질 수 있음 → 직접 포맷.
  static String _formatLocal(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}T'
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
