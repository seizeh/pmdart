import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/user_profile_screen.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_session.dart';
import 'helpers/fake_supabase.dart';

/// 사용자 프로필의 **게스트 가드** 회귀 가드.
///
/// 프로필은 게스트도 연다(피드의 닉네임 탭·사용자 검색). 그런데 화면에 로그인
/// 검사가 없어서 게스트가 Pawing 을 누르면 말없이 되돌아가고, 채팅은 "채팅방을 열
/// 수 없어요", 차단은 확인까지 받은 뒤 "잠시 후 다시 시도해주세요" 로 끝났다.
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
    FakeSupabase.on(
      'public_profiles',
      (_) => [
        {
          'id': 'u2',
          'nickname': '상대',
          'user_type': 'no_pet',
          'is_location_verified': false,
          'is_business': false,
        },
      ],
    );
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const UserProfileScreen(userId: 'u2', previewNickname: '상대'),
      ),
    );
    // 프로필 로드(여러 요청) + 진입 모션이 끝날 때까지.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Iterable<String> writes() => FakeSupabase.requests
      .where((r) => r.method != 'GET' && !r.url.path.contains('/rpc/public_'))
      .map((r) => '${r.method} ${r.url.path}');

  testWidgets('게스트가 Pawing 을 누르면 인증 벽이 뜬다', (tester) async {
    await pumpProfile(tester);

    // 통계 줄에도 같은 글자("Pawing" 라벨)가 있다 — 굵은 쪽이 버튼이다.
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data == 'Pawing' &&
            w.style?.fontWeight == FontWeight.w700,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(find.text('Pawing 은 로그인 후 할 수 있어요'), findsOneWidget);
    // 낙관적 토글도 일어나지 않는다.
    expect(find.text('Pawing 중'), findsNothing);
    expect(writes(), isEmpty);
  });

  testWidgets('게스트가 채팅을 누르면 인증 벽이 뜬다', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('채팅'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('채팅은 로그인 후 이용할 수 있어요'), findsOneWidget);
    expect(find.text('채팅방을 열 수 없어요'), findsNothing);
    expect(writes(), isEmpty);
  });

  testWidgets('게스트가 차단을 누르면 확인 창 대신 인증 벽이 뜬다', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.byIcon(Icons.block_outlined));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('차단은 로그인 후 할 수 있어요'), findsOneWidget);
    expect(find.text('이 사용자 차단'), findsNothing);
    expect(writes(), isEmpty);
  });
}
