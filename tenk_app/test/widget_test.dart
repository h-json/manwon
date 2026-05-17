import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tenk_app/presentation/login/login_screen.dart';

void main() {
  testWidgets('LoginScreen 렌더링 smoke test', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Tenk'), findsOneWidget);
    expect(find.text('카카오로 로그인'), findsOneWidget);
  });
}
