import 'package:dio/dio.dart';

/// 백엔드 `/api/media/{fileId}` 호출. 인증된 사용자가 자신의 amount 영상을 다운로드.
///
/// 응답은 inline content-disposition + Resource — dio 의 `download` 가 그대로 파일에 쓴다.
/// 영상 export 시 합성 입력을 모으는 단계에서 사용한다.
class MediaApi {
  MediaApi({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  /// [fileId] 영상을 [savePath] 로 저장. 도중 캔슬은 [cancelToken] 사용.
  /// [onReceiveProgress] 는 dio 가 직접 호출 (received, total). total 이 -1 이면 length 모름.
  Future<void> downloadToFile({
    required int fileId,
    required String savePath,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    await _dio.download(
      '/api/media/$fileId',
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }
}
