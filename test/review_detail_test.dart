import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/review_detail_screen.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:pawmate/widgets/review_cards.dart';

/// 후기 상세 — 게시글 상세 문법(카드 펼침/블롭 히어로/본문) 렌더 검증.
void main() {
  final review = ReviewCardData(
    author: '테스트유저',
    rating: 4,
    content: '사장님이 친절하고 시설이 깨끗해요',
    createdAt: DateTime(2026, 7, 10),
    isMine: true,
    visitNo: 2,
    seed: 'r1',
  );

  testWidgets('사진 없는 후기 상세 — 블롭 히어로에 본문, 칩·별점·작성자 표시', (tester) async {
    // 히어로(3:4)가 기본 뷰포트보다 높아 아래 본문이 지연 빌드되지 않으므로 확장.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: ReviewDetailScreen(review: review),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 짧은 글 — 본문은 히어로에만(아래 중복 없음).
    expect(find.text('사장님이 친절하고 시설이 깨끗해요'), findsOneWidget);
    expect(find.text('2번째 방문'), findsOneWidget);
    expect(find.text('내 후기'), findsOneWidget);
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('테스트유저'), findsOneWidget);
    expect(find.text('2026.7.10'), findsOneWidget);
  });

  testWidgets('내 후기 상세 — 삭제 버튼 → 확인 → onDelete 후 닫힘', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var deleted = false;
    final mine = ReviewCardData(
      author: '테스트유저',
      rating: 4,
      content: '삭제 테스트',
      isMine: true,
      seed: 'r2',
      onDelete: () async {
        deleted = true;
        return true;
      },
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReviewDetailScreen(review: mine),
                ),
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('후기를 삭제할까요?'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.byType(ReviewDetailScreen), findsNothing); // 삭제 후 닫힘
  });

  testWidgets('후기 카드 탭 → 상세 화면 push', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ListView(children: [ReviewCardGrid(reviews: [review])]),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(ReviewDetailScreen), findsOneWidget);
    expect(find.text('테스트유저'), findsOneWidget);
  });
}
