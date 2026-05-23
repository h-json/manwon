import 'package:flutter/foundation.dart';

/// 기록 수정 시 영상 처리 방식. 백엔드 `AmountUpdateRequest.VideoAction` 과 1:1 매칭.
enum VideoAction {
  /// 기존 영상 유지 — video part 미전송
  keep,
  /// 기존 영상 + 디스크 파일 삭제 — video part 미전송
  remove,
  /// 기존 영상 삭제 후 새 video part 저장 (video part 필수)
  replace,
}

@immutable
class AmountMediaFile {
  const AmountMediaFile({
    required this.fileId,
    required this.filePath,
    required this.originalName,
  });

  final int fileId;
  final String filePath;
  final String originalName;

  factory AmountMediaFile.fromJson(Map<String, dynamic> json) {
    return AmountMediaFile(
      fileId: (json['fileId'] as num).toInt(),
      filePath: json['filePath'] as String,
      originalName: json['originalName'] as String,
    );
  }
}

@immutable
class Amount {
  const Amount({
    required this.id,
    required this.challengeId,
    required this.category,
    required this.content,
    required this.amount,
    required this.noSpend,
    required this.memo,
    required this.spentDt,
    required this.mediaFiles,
  });

  final int id;
  final int challengeId;
  final String? category;
  final String? content;
  final int amount;
  final bool noSpend;

  /// 사용자가 기록 시 남긴 자유 메모 (nullable). 영상 export 시 자막 디폴트를 오버라이드한다
  /// (있으면 그 값, 없으면 지출="내용 금액원" / 무지출="무지출").
  final String? memo;

  /// 사용자가 선택한 "지출 발생 일시" (날짜 부분이 챌린지 기간 안에 있어야 함).
  /// 백엔드는 `LocalDateTime` (타임존 없음)으로 보낸다.
  final DateTime spentDt;
  final List<AmountMediaFile> mediaFiles;

  factory Amount.fromJson(Map<String, dynamic> json) {
    final media = (json['mediaFiles'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AmountMediaFile.fromJson)
        .toList(growable: false);
    return Amount(
      id: (json['amountId'] as num).toInt(),
      challengeId: (json['challengeId'] as num).toInt(),
      category: json['category'] as String?,
      content: json['content'] as String?,
      amount: (json['amount'] as num).toInt(),
      noSpend: json['noSpend'] as bool,
      memo: json['memo'] as String?,
      spentDt: DateTime.parse(json['spentDt'] as String),
      mediaFiles: media,
    );
  }
}

/// 지출/무지출 기록 추가 응답. [removedNoSpendCount] 는 지출 등록 시 같은 날 무지출이 자동
/// 삭제된 건수 (정상 흐름에선 0 또는 1). 0보다 크면 사용자에게 "오늘 무지출 기록이 취소되었어요"
/// 같은 안내를 띄운다.
@immutable
class AmountRecordResult {
  const AmountRecordResult({
    required this.amount,
    required this.removedNoSpendCount,
  });

  final Amount amount;
  final int removedNoSpendCount;

  factory AmountRecordResult.fromJson(Map<String, dynamic> json) {
    return AmountRecordResult(
      amount: Amount.fromJson(json['amount'] as Map<String, dynamic>),
      removedNoSpendCount: (json['removedNoSpendCount'] as num).toInt(),
    );
  }
}
