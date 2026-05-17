/// 카카오 네이티브 앱 키. 카카오 디벨로퍼스 → 앱 설정 → 앱 키 → "네이티브 앱 키".
///
/// 이 값을 바꿀 때는 다음 세 곳을 모두 같이 교체해야 한다.
///   1) 여기 (KakaoSdk.init)
///   2) android/app/build.gradle.kts 의 manifestPlaceholders["kakaoNativeAppKey"]
///   3) ios/Runner/Info.plist 의 CFBundleURLSchemes "kakao{KEY}"
const String kakaoNativeAppKey = '589078d3c7daa590c71d9a6e77080b18';
