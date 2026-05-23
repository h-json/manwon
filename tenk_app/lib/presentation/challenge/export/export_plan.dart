import 'package:flutter/foundation.dart';

import '../../../data/amount/amount.dart';

/// 영상 합본 export 의 세션 상태. 선택 화면 → prefetch → 합성 까지 흘러간다.
///
/// **세션 한정** — 화면 떠나면 사라진다. 자막 편집은 `amount.memo` 와 분리된 일회용 오버라이드라
/// DB 에 저장되지 않는다.
///
/// 무지출이면서 영상이 없는 클립은 [localVideoPath] 가 null → 합성 단계에서 2초 텍스트 카드로 삽입.
@immutable
class ExportClipPlan {
  const ExportClipPlan({
    required this.source,
    required this.comment,
    required this.localVideoPath,
  });

  final Amount source;
  final String comment;

  /// prefetch 단계에서 다운로드된 로컬 파일 경로. 무지출+영상없음 케이스는 null.
  final String? localVideoPath;
}

@immutable
class ExportPlan {
  const ExportPlan({required this.clips});

  /// 합성에 들어갈 클립 — 이미 spentDt ASC 로 정렬돼 있다고 가정 (호출처가 정렬해서 넘김).
  final List<ExportClipPlan> clips;
}
