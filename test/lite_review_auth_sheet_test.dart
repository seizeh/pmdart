import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:pawmate/widgets/lite_review_auth_sheet.dart';

import 'helpers/fake_supabase.dart';

/// 간이 인증 시트의 **재발송** 회귀 가드.
///
/// 실제 결함: 코드를 보내고 나면 번호 칸을 `enabled: false` 로 잠그는데, "재발송"
/// 버튼이 그 칸의 suffixIcon 이었다. 비활성 TextField 는 꾸밈(suffix 포함) 전체의
/// 포인터를 무시하므로 쿨다운이 끝나 버튼이 켜져 보여도 눌리지 않았다 — 문자가
/// 안 오면 시트를 닫고 처음부터 다시 하는 수밖에 없었다.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Supabase 초기화가 딥링크(app_links) 이벤트 채널을 구독한다. 테스트엔 그
    // 플러그인이 없어 MissingPluginException 이 **실제 비동기로** 뒤늦게 터지는데,
    // 이 파일은 아래에서 실제 비동기를 돌리므로 그 예외가 테스트 실패로 잡힌다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    await FakeSupabase.init();
  });

  setUp(FakeSupabase.reset);

  // Edge Function 호출은 본문 인코딩·응답 해석을 별도 isolate 에 맡긴다 — 테스트의
  // 가짜 시계로는 진행되지 않으므로, 화면에 반영될 때까지 실제 비동기를 돌린다.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('재발송은 번호 칸이 잠긴 뒤에도 눌린다', (tester) async {
    var sends = 0;
    FakeSupabase.on('send-phone-code', (_) {
      sends++;
      return {'ok': true, 'expires_in_sec': 180};
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLiteReviewAuthSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '01012345678');
    await tester.pump();
    await tester.tap(find.text('인증번호 받기'));
    await settleUntil(tester, () => find.text('60초').evaluate().isNotEmpty);
    expect(sends, 1);
    // 발송 뒤 번호는 고칠 수 없다(다른 번호로 바꿔 인증하는 것을 막는다).
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      isFalse,
    );

    // 포인터를 다시 받게 했어도 잠긴 칸은 눌러서 입력을 열 수 없다.
    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isFalse);

    // 서버 쿨다운(60초)이 지나면 버튼이 "재발송" 으로 돌아온다.
    for (var i = 0; i < 61; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('재발송'), findsOneWidget);

    await tester.tap(find.text('재발송'));
    await settleUntil(tester, () => sends == 2);
    expect(sends, 2, reason: '재발송이 서버 호출로 이어져야 한다');
  });
}
