import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/motion/motion.dart';

/// 장문 본문 스크롤 vs 카드 축소 제스처의 우선순위 가드.
///
/// 실제 사고: 쇼츠형 상세의 바깥 리스트는 높이 1장짜리(스크롤 범위 0)라
/// CollapsibleView 의 "최상단에서만 축소" 게이트가 항상 열려 있었고, 펼친
/// 본문(SingleChildScrollView)은 제스처 아레나 밖 raw Listener 와 **동시에**
/// 반응해 — 본문을 스크롤하는데 화면이 닫혀버렸다. CollapseScrollGuard 는
/// "스크롤에 쓰인 제스처는 끝까지 스크롤 전용(최상단에 닿아도 그 손가락으론
/// 축소 금지), 떼었다 다시 당겨야 축소"를 보장한다 — 최상단 도착과 동시에
/// 화면이 닫히는 과민함(실사용 피드백)을 막는 래치 방식.
void main() {
  const viewport = Size(800, 600); // 테스트 기본 서피스

  Future<Animation<double>?> openDetail(WidgetTester tester) async {
    Animation<double>? progress;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => CollapsibleView(
                      originRect: const Rect.fromLTWH(150, 300, 100, 120),
                      card: null,
                      scrollController: ScrollController(),
                      contentAlignment: Alignment.center,
                      builder: (context, physics) => Builder(
                        builder: (inner) {
                          progress = CollapseProgress.of(inner);
                          // 쇼츠형 상세 구조 재현: 바깥 리스트는 뷰포트 1장
                          // (스크롤 범위 0) + 중앙에 펼친 본문 패널.
                          return Scaffold(
                            body: ListView(
                              physics: physics,
                              padding: EdgeInsets.zero,
                              children: [
                                SizedBox(
                                  height: viewport.height,
                                  child: Center(
                                    child: SizedBox(
                                      height: 400,
                                      child: CollapseScrollGuard(
                                        builder: (context, controller) =>
                                            SingleChildScrollView(
                                              controller: controller,
                                              physics:
                                                  const ClampingScrollPhysics(),
                                              child: Column(
                                                children: [
                                                  for (var i = 0; i < 50; i++)
                                                    SizedBox(
                                                      height: 50,
                                                      child: Text('줄 $i'),
                                                    ),
                                                ],
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle(); // 확장 전환 완주 → 진행도 1
    return progress;
  }

  ScrollPosition innerPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CollapseScrollGuard),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testWidgets('본문이 스크롤 위에 있으면 아래 당김은 스크롤만 한다(축소 금지)', (tester) async {
    final progress = await openDetail(tester);
    expect(progress!.value, 1.0);

    // 본문을 300px 내려 읽던 상태로 만든다.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(innerPosition(tester).pixels, greaterThan(200));

    // 본문 위에서 아래로 150px 당김 — 본문이 위로 되감길 뿐 축소는 없어야 한다.
    final g = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(progress.value, 1.0); // 축소 시작 안 됨
    expect(innerPosition(tester).pixels, lessThan(300)); // 스크롤은 소비됨
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(CollapsibleView), findsOneWidget); // 안 닫힘
  });

  testWidgets('같은 당김으론 최상단에 닿아도 안 닫히고, 떼었다 다시 당기면 닫힌다', (tester) async {
    final progress = await openDetail(tester);

    // 100px 만 내려두고, 그보다 훨씬 큰 당김 한 번 — 스크롤이 소진돼
    // 최상단에 닿아도 이 손가락으론 축소가 시작되면 안 된다(래치).
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    final g = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(innerPosition(tester).pixels, 0); // 스크롤 소진
    expect(progress!.value, 1.0); // 그래도 축소는 없다
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(CollapsibleView), findsOneWidget); // 안 닫힘

    // 손을 뗀 뒤 새 당김 — 이제 최상단이므로 축소로 이어져 닫힌다.
    final g2 = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < 10; i++) {
      await g2.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(progress.value, lessThan(1.0)); // 축소 진행 중
    await g2.up();
    await tester.pumpAndSettle();
    expect(find.byType(CollapsibleView), findsNothing);
  });

  testWidgets('본문이 처음부터 최상단이면 기존처럼 바로 축소된다(회귀 가드)', (tester) async {
    final progress = await openDetail(tester);

    final g = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(progress!.value, lessThan(1.0));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(CollapsibleView), findsNothing);
  });
}
