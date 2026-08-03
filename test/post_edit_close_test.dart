import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/community.dart';
import 'package:pawmate/screen/post_edit_screen.dart';
import 'package:pawmate/theme/app_theme.dart';

import 'helpers/fake_supabase.dart';

/// 게시글 수정 화면의 **닫기** 회귀 가드.
///
/// 실제 사고: 수정 화면을 작성 화면과 같은 히어로 에디터로 바꾸면서 앱바를 없앴는데,
/// 앱바의 뒤로가기까지 함께 사라졌다. 작성 화면은 CollapseRoute 로 열려 아래로
/// 쓸어내리면 닫히지만 수정은 일반 push 라 그 제스처가 없다. 그래서 **수정이 잠긴
/// 게시글**(약속 완료)에 들어가면 저장도 안 되고 나갈 수도 없었다.
void main() {
  setUpAll(() async {
    await FakeSupabase.init();
  });

  Future<void> pumpEdit(WidgetTester tester, Post post) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PostEditScreen(post: post),
      ),
    );
    await tester.pump();
  }

  testWidgets('닫기 버튼은 항상 있다 — 편집 불가 게시글에서도', (tester) async {
    await pumpEdit(tester, _freePost);
    expect(find.byTooltip('닫기'), findsOneWidget);
  });

  testWidgets('고친 게 없으면 닫기가 바로 닫는다', (tester) async {
    await pumpEdit(tester, _freePost);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    // 확인 다이얼로그 없이 그대로 빠져나간다.
    expect(find.text('수정을 취소할까요?'), findsNothing);
  });

  testWidgets('고친 게 있으면 닫기 전에 버릴지 묻는다', (tester) async {
    await pumpEdit(tester, _freePost);
    await tester.enterText(find.byType(TextField).first, '바뀐 제목');
    await tester.pump();
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('수정을 취소할까요?'), findsOneWidget);
    // '계속 수정' 을 고르면 화면에 남는다.
    await tester.tap(find.text('계속 수정'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('닫기'), findsOneWidget);
  });
}

/// 자유 게시글 + 일정 없음 → 잠금 조회(네트워크)를 타지 않는다.
final _freePost = Post(
  id: 'p1',
  category: 'free',
  title: '원래 제목',
  content: '원래 내용',
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
);
