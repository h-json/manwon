/// 백엔드 base URL.
///
/// 빌드 시 `--dart-define=API_BASE_URL=...`로 주입 가능. 기본값은 Android 에뮬레이터에서
/// 호스트 머신을 가리키는 `http://10.0.2.2:8080`. iOS 시뮬레이터는 `http://localhost:8080`,
/// 실기기는 같은 네트워크의 PC IP(`http://192.168.x.x:8080`)를 주입할 것.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);
