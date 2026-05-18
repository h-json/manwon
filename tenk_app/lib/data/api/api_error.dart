import 'package:dio/dio.dart';

/// 백엔드 `ApiResponse.error` envelope을 풀어 사용자 친화적 메시지로 변환한 예외.
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final String? code;
  final String message;

  @override
  String toString() => message;
}

/// 백엔드 응답이 `{success:false, error:{code,message}}`이면 그 안의 message를 꺼내고,
/// 그 외 네트워크/파싱 오류는 dio의 message를 그대로 사용한다. UI에서 catch한 객체를 그대로 던져넣어도 안전.
ApiException toApiException(Object error) {
  if (error is ApiException) return error;
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      if (err is Map<String, dynamic>) {
        return ApiException(
          err['code'] as String?,
          (err['message'] as String?) ?? '알 수 없는 오류가 발생했어요.',
        );
      }
    }
    return ApiException(null, error.message ?? '네트워크 오류가 발생했어요.');
  }
  return ApiException(null, error.toString());
}
