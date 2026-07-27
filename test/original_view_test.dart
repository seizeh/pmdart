import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/community.dart';
import 'package:pawmate/screen/review_detail_screen.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:pawmate/widgets/post_media_hero.dart';
import 'package:pawmate/widgets/review_cards.dart';

import 'helpers/fake_network_image.dart';

/// 원본 보기 — 미디어를 탭(또는 앱바 아이콘)하면 오버레이(블러)가 걷힌 뒤
/// 사진이 화면을 꽉 채우는 cover 에서 원본 비율(contain)로 줄어들며 확대/이동이
/// 열리고, 다시 토글하면 cover 로 복귀한다. 게시글 상세·후기 상세 공용.
void main() {
  // 2:1 사진 — 400×800 박스에서 contain 렌더(400×200)를 4배 키운 것이 cover 다.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final restore = await installFakeNetworkImage(width: 400, height: 200);
    addTearDown(restore);
  });

  /// 뷰어 안쪽(가장 깊은) Transform 이 cover ↔ contain 보간 배율
  /// — 바깥 Transform 은 InteractiveViewer 자신의 확대/이동 행렬이다.
  double scaleOf(WidgetTester tester) => tester
      .widgetList<Transform>(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(Transform),
        ),
      )
      .last
      .transform
      .getMaxScaleOnAxis();

  /// 실제 디코딩이 끝나야 원본 비율을 읽는다(runAsync 안에서만 가능).
  Future<void> pumpLoaded(WidgetTester tester, Widget app) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  /// 오버레이 페이드(200ms) → 축소(420ms) 완료까지.
  Future<void> settleFit(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('게시글 상세 — 사진 탭: 오버레이가 걷힌 뒤 원본 비율로 축소, 다시 탭하면 cover 복귀', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final origin = ValueNotifier<bool>(false);
    addTearDown(origin.dispose);
    final toggles = <bool>[];
    origin.addListener(() => toggles.add(origin.value));

    await pumpLoaded(
      tester,
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: PostMediaHero(post: _photoPost, originView: origin),
        ),
      ),
    );

    // 기본 상태 — 화면을 꽉 채우는 cover, 확대/이동은 잠겨 있다.
    expect(scaleOf(tester), closeTo(4, 0.001));
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .scaleEnabled,
      isFalse,
    );

    // 탭 — 오버레이부터 숨고(즉시 통지), 축소는 그다음 동작.
    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump();
    expect(toggles, [true]);
    expect(scaleOf(tester), closeTo(4, 0.001)); // 아직 cover

    await settleFit(tester);
    expect(scaleOf(tester), closeTo(1, 0.001)); // 원본 비율
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.scaleEnabled, isTrue); // 이 상태에서 확대/축소·이동 가능
    expect(viewer.panEnabled, isTrue);

    // 다시 탭 — cover 로 확대하며 오버레이 복귀.
    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump();
    expect(toggles, [true, false]);
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaleOf(tester), closeTo(4, 0.001));
  });

  testWidgets('후기 상세 — 사진 탭: 원본 비율로 축소되고 페이저·리스트 스크롤이 잠긴다', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpLoaded(
      tester,
      MaterialApp(
        theme: AppTheme.light(),
        home: const ReviewDetailScreen(
          review: ReviewCardData(
            author: '테스트유저',
            rating: 5,
            content: '사진 후기',
            photoUrls: ['https://example.com/r1.jpg'],
            seed: 'r1',
          ),
        ),
      ),
    );

    expect(scaleOf(tester), closeTo(4, 0.001));
    // 앱바 좌측 원본 보기 아이콘(영상 글에서 유일한 입구 — 사진에도 함께 제공).
    expect(find.byTooltip('원본 보기'), findsOneWidget);

    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump();
    await settleFit(tester);
    expect(scaleOf(tester), closeTo(1, 0.001));

    // 확대/이동이 제스처를 가져가도록 페이저·리스트는 잠긴다.
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    expect(
      tester.widget<ListView>(find.byType(ListView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    // 앱바 아이콘으로도 복귀(사진은 몰입을 위해 숨지만 상태는 이 아이콘과 공유).
    await tester.tap(find.byType(InteractiveViewer), warnIfMissed: false);
    await tester.pump(); // 되돌리는 애니메이션 시작 프레임
    await tester.pump(const Duration(milliseconds: 500));
    expect(scaleOf(tester), closeTo(4, 0.001));
    expect(find.byTooltip('원본 보기'), findsOneWidget);
  });
}

final _photoPost = Post(
  id: 'p1',
  category: '일상',
  title: '산책 사진',
  content: '오늘의 산책',
  userId: 'u1',
  authorNickname: '테스트유저',
  authorUserType: 'personal',
  createdAt: DateTime(2026, 7, 20),
  scheduledAt: null,
  location: '역삼동',
  heartCount: 0,
  commentCount: 0,
  viewCount: 0,
  progressStatus: 'open',
  hearted: false,
  imageUrl: 'https://example.com/photo.jpg',
);
