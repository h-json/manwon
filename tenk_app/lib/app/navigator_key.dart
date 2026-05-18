import 'package:flutter/widgets.dart';

/// MaterialApp.navigatorKey에 박는 전역 키.
///
/// 위젯 트리 밖(예: dio interceptor)에서 로그아웃을 트리거할 때 BuildContext 없이
/// 라우터에 접근하기 위해 필요. 일반 화면 코드에서는 사용하지 말 것 (대신 `Navigator.of(context)`).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
