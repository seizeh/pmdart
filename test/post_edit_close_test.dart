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

  // 실제 결함: 잠긴 글에서 제목은 잠겼는데 본문 입력칸만 살아 있었다. 저장은
  // 막혀 있으니 적은 내용은 갈 곳이 없고, 그 상태로 닫으면 "수정을 취소할까요?"
  // 까지 물었다 — 잠긴 글은 고칠 수 없어 바로 닫힌다는 전제가 깨진다.
  testWidgets('잠긴 게시글은 제목·본문 입력이 모두 잠긴다', (tester) async {
    FakeSupabase.on('post_edit_locked', (_) => true);
    await pumpEdit(tester, _lockedWalkPost);
    await tester.pump(); // 잠금 조회 응답 반영
    await tester.pump();

    expect(find.textContaining('약속이 완료된 게시글'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, hasLength(2), reason: '제목 + 본문');
    expect(
      fields.map((f) => f.enabled),
      everyElement(isFalse),
      reason: '잠긴 글은 어느 칸에도 입력할 수 없다',
    );
  });
}

/// 약속이 완료된 산책 게시글 — 잠금 조회(post_edit_locked)를 탄다.
final _lockedWalkPost = Post(
  id: 'p2',
  category: 'walk',
  title: '원래 제목',
  content: '원래 내용',
  userId: 'u1',
  authorNickname: '테스트유저',
  authorUserType: 'personal',
  createdAt: DateTime(2026, 7, 20),
  scheduledAt: DateTime(2026, 7, 25, 10),
  location: '역삼동',
  heartCount: 0,
  commentCount: 0,
  viewCount: 0,
  progressStatus: 'done',
  hearted: false,
);

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
