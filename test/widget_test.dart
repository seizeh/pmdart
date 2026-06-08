// PawMate 기본 스모크 테스트.

import 'package:flutter_test/flutter_test.dart';

import 'package:pawmate/main.dart';

void main() {
  testWidgets('첫 화면(WelcomeScreen)이 렌더된다', (WidgetTester tester) async {
    // PawMateApp 은 Supabase 초기화 없이 WelcomeScreen 을 띄운다.
    await tester.pumpWidget(const PawMateApp());

    // 환영 화면의 핵심 카피/버튼이 보이는지 확인.
    expect(find.text('전화번호로 시작하기'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
  });
}
