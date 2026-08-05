import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/terms_screen.dart';
import 'package:pawmate/theme/app_theme.dart';

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

/// 문서 로드(비동기) + 애니메이션을 한 프레임 이상 진행시킨다.
///
/// `pumpAndSettle` 은 쓰지 않는다 — 스크롤바 페이드 등 자체적으로 멈추지 않는
/// 애니메이션이 남아 있으면 정착하지 못하고 타임아웃한다.
Future<void> _settle(WidgetTester tester) async {
  // 한두 프레임으로는 부족하다 — 에셋 로드 future 해소와 ensureVisible(400ms)
  // 애니메이션이 겹쳐 있어 프레임 수에 따라 결과가 갈렸다.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  // 번들 에셋(rootBundle)을 읽으려면 바인딩이 먼저 서야 한다 — 없으면 문서 로드가
  // 끝나지 않아 스피너가 계속 돌고 pumpAndSettle 이 타임아웃한다.
  TestWidgetsFlutterBinding.ensureInitialized();

  // 같은 문서를 여러 테스트에서 다시 여는 것은 피한다 — 테스트 간 에셋 캐시가
  // 초기화되는 시점과 겹치면 두 번째 로드가 프레임 안에 끝나지 않아 불안정했다.
  testWidgets('열람 모드 — 개정 이력 버튼이 보이고, 누르면 부칙으로 이동한다', (tester) async {
    await tester.pumpWidget(_app(TermsScreen.service()));
    await _settle(tester);

    expect(find.text('개정 이력'), findsOneWidget);

    // ⚠️ findsNothing 으로는 확인할 수 없다 — SingleChildScrollView 는 화면 밖
    //    위젯도 전부 빌드하므로 find 는 처음부터 찾아낸다. 위치로 봐야 한다.
    final screenH =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final before = tester.getTopLeft(find.text('부칙')).dy;
    expect(before, greaterThan(screenH), reason: '문서 맨 끝이라 처음엔 화면 아래');

    await tester.tap(find.text('개정 이력'));
    await _settle(tester);

    final after = tester.getTopLeft(find.text('부칙')).dy;
    expect(after, lessThan(before));
    expect(after, inInclusiveRange(0, screenH), reason: '화면 안으로 들어와야 한다');
  });

  testWidgets('가입 동의 단계에서는 버튼을 숨긴다 — 끝까지 읽기 게이트 우회 방지', (tester) async {
    await tester.pumpWidget(_app(TermsScreen.service(agree: true)));
    await _settle(tester);

    expect(find.text('개정 이력'), findsNothing);
    // 게이트는 그대로 — 아직 안 읽었으므로 동의 버튼이 잠겨 있다.
    expect(find.text('약관을 끝까지 읽어주세요'), findsOneWidget);
  });

  testWidgets('처리방침은 제목이 달라도(…의 변경) 찾아낸다', (tester) async {
    await tester.pumpWidget(_app(TermsScreen.privacy()));
    await _settle(tester);

    expect(find.text('개정 이력'), findsOneWidget);
    final target = find.text('14. 개인정보 처리방침의 변경');
    final screenH =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getTopLeft(target).dy, greaterThan(screenH));

    await tester.tap(find.text('개정 이력'));
    await _settle(tester);

    expect(tester.getTopLeft(target).dy, inInclusiveRange(0, screenH));
  });

  testWidgets('개정 이력 절이 없는 문서에는 버튼이 없다', (tester) async {
    // 간이 후기 이용조건에는 부칙·변경 절이 없다.
    await tester.pumpWidget(_app(TermsScreen.liteReview()));
    await _settle(tester);

    expect(find.text('개정 이력'), findsNothing);
  });
}
