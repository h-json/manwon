/// 백엔드 공통 응답 envelope `{ success, data, error }` 파서.
///
/// 모든 `*Api` 클래스가 응답에서 `data`를 꺼낼 때 이걸 거치도록 한다.
/// `_unwrapData`/`_unwrapList`를 도메인마다 복붙하지 말 것.
library;

Map<String, dynamic> unwrapData(dynamic body) {
  final map = body as Map<String, dynamic>;
  final data = map['data'];
  if (data is Map<String, dynamic>) return data;
  throw const FormatException('Unexpected ApiResponse envelope: missing data');
}

List<Map<String, dynamic>> unwrapList(dynamic body) {
  final map = body as Map<String, dynamic>;
  final data = map['data'];
  if (data is List) return data.cast<Map<String, dynamic>>();
  throw const FormatException('Unexpected ApiResponse envelope: missing list');
}
