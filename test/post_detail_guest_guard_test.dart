import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/community.dart';
import 'package:pawmate/motion/heart_burst.dart';
import 'package:pawmate/screen/post_detail_screen.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_session.dart';
import 'helpers/fake_supabase.dart';

/// 게시글 상세의 **게스트 가드** 회귀 가드.
///
/// 실제 결함: 상세 화면은 게스트 여부를 생성자 인자(`isGuest`)로만 알았다. 피드는
/// 값을 넘기지만 사용자 프로필·반려동물 프로필의 게시글 목록은 넘기지 않는다.
/// 두 프로필은 게스트도 열 수 있으므로(피드의 닉네임 탭·사용자 검색), 그 길로 들어온
/// 게스트가 하트를 누르면 인증 벽 대신 "잠시 후 다시 시도해주세요" 가 떴다 —
/// 기다려도 될 일이 아닌데 기다리라고 안내한 셈이다.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await FakeSupabase.init();
  });

  setUp(() async {
    FakeSupabase.reset();
    await SessionManager.instance.clear();
  });

  // 프로필 화면들이 여는 방식 그대로 — isGuest 를 넘기지 않는다.
  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PostDetailScreen(post: _post),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('비로그인이면 isGuest 를 안 넘겨도 하트가 인증 벽을 띄운다', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byType(HeartButton));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(find.text('하트는 로그인 후 누를 수 있어요'), findsOneWidget);
    expect(find.text('잠시 후 다시 시도해주세요'), findsNothing);
    // 서버로는 아무것도 보내지 않는다(조회수·팔로우 조회 포함).
    expect(
      FakeSupabase.requests.where((r) => r.method != 'GET'),
      isEmpty,
      reason: '게스트는 쓰기 요청을 만들지 않는다',
    );
  });

  testWidgets('로그인 상태면 하트가 그대로 서버로 간다', (tester) async {
    await SessionManager.instance.setSession(
      jwtWithExp(nowSec() + 3600),
      const AuthUser(
        id: 'u9',
        username: 'me',
        nickname: '나',
        userType: 'no_pet',
      ),
      refresh: 'r1',
    );
    await pumpDetail(tester);

    await tester.tap(find.byType(HeartButton));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('로그인이 필요해요'), findsNothing);
    expect(
      FakeSupabase.requests.where(
        (r) => r.method == 'POST' && r.url.path.contains('post_hearts'),
      ),
      hasLength(1),
    );
  });
}

/// 사진 없는 자유 게시글 — 미디어 로딩 없이 오버레이(하트)만 뜬다.
final _post = Post(
  id: 'p1',
  category: 'free',
  title: '제목',
  content: '내용',
  userId: 'u1',
  authorNickname: '작성자',
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
