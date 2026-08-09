import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:pawmate/widgets/app_invite_dialog.dart';

/// 웹 앱 유도 다이얼로그의 **플랫폼 분기** — 방문자가 갈 수 있는 곳이 하나만
/// 보여야 한다. iOS 만 출시된 상태에서 안드로이드 방문자에게 App Store 버튼을
/// 보여 주면 막다른 길이다.
///
/// 스토어 주소는 컴파일 상수(`Env`)라 테스트에서 바꿀 수 없다. 그래서 여기서는
/// **현재 빌드 설정 기준의 불변식**만 지킨다: 어떤 플랫폼에서도 다른 플랫폼의
/// 스토어 버튼이 함께 뜨지 않는다.
/// ⚠️ 되돌리기는 **테스트 본문 안**에서 끝나야 한다. flutter_test 는 본문이
/// 끝나는 시점에 foundation 디버그 변수가 원래대로인지 검사하는데, addTearDown
/// 은 그 검사보다 늦게 돈다(테스트가 통째로 실패한다).
Future<void> _withPlatform(
  WidgetTester tester,
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await _pump(tester);
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => AppInviteDialog.show(context, feature: '채팅'),
          child: const Text('열기'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('안드로이드 방문자에게 App Store 버튼을 보여주지 않는다', (tester) async {
    await _withPlatform(tester, TargetPlatform.android, () async {
      expect(find.textContaining('App Store'), findsNothing);
    });
  });

  // Play 출시 전에는 안드로이드 방문자가 갈 곳이 테스터 신청뿐이다 — 여기가
  // 비면 "출시 준비 중" 만 뜨는 막다른 다이얼로그가 된다(TESTER_FORM_URL 회귀 방지).
  testWidgets('안드로이드 방문자에게 테스터 신청 버튼을 보여준다', (tester) async {
    await _withPlatform(tester, TargetPlatform.android, () async {
      expect(find.textContaining('테스터 신청'), findsOneWidget);
    });
  });

  testWidgets('iOS 방문자에게 Google Play 버튼을 보여주지 않는다', (tester) async {
    await _withPlatform(tester, TargetPlatform.iOS, () async {
      expect(find.textContaining('Google Play'), findsNothing);
    });
  });

  testWidgets('막다른 다이얼로그가 되지 않는다 — 닫는 길은 항상 있다', (tester) async {
    await _withPlatform(tester, TargetPlatform.android, () async {
      // 문구가 '나중에 할래요'/'닫기' 중 무엇이든 닫는 버튼은 반드시 하나 있다.
      expect(
        find.byWidgetPredicate((w) => w is TextButton && w.child is Text),
        findsWidgets,
      );
    });
  });

  testWidgets('무엇 때문에 막혔는지 문구에 드러난다', (tester) async {
    await _withPlatform(tester, TargetPlatform.iOS, () async {
      // 제목이 막힌 기능을 그대로 받는다 — '채팅은 앱에서 이용할 수 있어요'.
      expect(find.textContaining('채팅은'), findsOneWidget);
    });
  });
}
