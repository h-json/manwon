import 'dart:convert';

import 'package:dio/dio.dart';

import '../api/api_response.dart';
import 'amount.dart';

/// 백엔드 `/api/challenges/{id}/amounts/*` 호출. 모두 인증 필요.
///
/// 기록 추가는 multipart/form-data. `request` part는 JSON, `video` part는 파일.
/// 백엔드 컨트롤러가 `@RequestPart("request") AmountCreateRequest` + `@RequestPart("video") MultipartFile`로 받음.
class AmountApi {
  AmountApi({required Dio authDio}) : _dio = authDio;

  final Dio _dio;

  /// 지출/무지출 기록 추가. 무지출이면 [dateTime] 은 백엔드가 무시(서버 now 강제)하므로 null 로 보낸다.
  Future<AmountRecordResult> record({
    required int challengeId,
    required bool noSpend,
    DateTime? dateTime,
    String? category,
    String? content,
    int? amount,
    String? memo,
    String? videoPath,
  }) async {
    final requestJson = jsonEncode({
      'category': category,
      'content': content,
      'amount': amount,
      'noSpend': noSpend,
      'memo': memo,
      'dateTime': dateTime != null ? _formatLocalDateTime(dateTime) : null,
    });
    final parts = <String, dynamic>{
      // 백엔드가 `request` part의 Content-Type을 application/json으로 기대 → MultipartFile.fromString + contentType 명시.
      'request': MultipartFile.fromString(
        requestJson,
        contentType: DioMediaType('application', 'json'),
      ),
    };
    if (videoPath != null) {
      parts['video'] = await MultipartFile.fromFile(
        videoPath,
        contentType: DioMediaType('video', 'mp4'),
      );
    }
    final form = FormData.fromMap(parts);
    final res = await _dio.post(
      '/api/challenges/$challengeId/amounts',
      data: form,
    );
    return AmountRecordResult.fromJson(unwrapData(res.data));
  }

  Future<List<Amount>> list(int challengeId) async {
    final res = await _dio.get('/api/challenges/$challengeId/amounts');
    return unwrapList(res.data).map(Amount.fromJson).toList(growable: false);
  }

  /// 기록 수정. multipart PUT — `request` JSON part + 선택적 `video` part.
  ///
  /// - 지출: [hour]/[minute] 으로 시간만 변경 (날짜는 백엔드가 기존 spentDt 의 LocalDate 유지).
  ///   둘 다 null 이면 백엔드에서 시간 변경 없음.
  /// - 무지출: 시간/카테고리/내용/금액은 백엔드가 무시. memo 만 반영.
  /// - 영상: [videoAction] 이 [VideoAction.replace] 면 [videoPath] 필수.
  Future<Amount> update({
    required int challengeId,
    required int amountId,
    required bool noSpend,
    String? category,
    String? content,
    int? amount,
    String? memo,
    int? hour,
    int? minute,
    required VideoAction videoAction,
    String? videoPath,
  }) async {
    final requestJson = jsonEncode({
      'category': category,
      'content': content,
      'amount': amount,
      'memo': memo,
      'time': (hour != null && minute != null) ? _formatLocalTime(hour, minute) : null,
      'videoAction': videoAction.name.toUpperCase(),
    });
    final parts = <String, dynamic>{
      'request': MultipartFile.fromString(
        requestJson,
        contentType: DioMediaType('application', 'json'),
      ),
    };
    if (videoAction == VideoAction.replace && videoPath != null) {
      parts['video'] = await MultipartFile.fromFile(
        videoPath,
        contentType: DioMediaType('video', 'mp4'),
      );
    }
    final form = FormData.fromMap(parts);
    final res = await _dio.put(
      '/api/challenges/$challengeId/amounts/$amountId',
      data: form,
    );
    return Amount.fromJson(unwrapData(res.data));
  }

  Future<void> delete({required int challengeId, required int amountId}) async {
    await _dio.delete('/api/challenges/$challengeId/amounts/$amountId');
  }

  /// 백엔드 `LocalTime` 은 `HH:mm:ss` 포맷을 기대한다.
  static String _formatLocalTime(int hour, int minute) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(hour)}:${two(minute)}:00';
  }

  /// 백엔드 `LocalDateTime`은 타임존 없는 `yyyy-MM-ddTHH:mm:ss`를 기대.
  /// `DateTime.toIso8601String()`은 UTC면 `Z`를 붙여 파서를 깨므로 직접 포맷한다.
  static String _formatLocalDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}T'
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
