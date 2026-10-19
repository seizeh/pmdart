import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/chat.dart';
import 'package:pawmate/screen/chat_room_screen.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_session.dart';
import 'helpers/fake_supabase.dart';

/// 채팅방 동영상 첨부의 **길이 초과** 회귀 가드.
///
/// `StorageService.pickVideo` 는 60초를 넘는 영상에 `StateError` 를 던진다. 게시글
/// 작성·수정·시설 후기는 그 예외를 받아 토스트로 바꾸는데 채팅방만 받지 않았다 —
/// 긴 영상을 고르면 아무 안내 없이 첨부가 끝나 버렸다.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Supabase 초기화가 구독하는 딥링크 채널 — 테스트엔 플러그인이 없다.
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
    // 갤러리에서 영상 하나를 고른 것으로 한다.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => call.method == 'pickVideo' ? '/tmp/long.mp4' : null,
    );
    // 그 영상의 길이는 90초.
    messenger.setMockMethodCallHandler(
      const MethodChannel('video_compress'),
      (call) async => call.method == 'getMediaInfo'
          ? jsonEncode({'path': '/tmp/long.mp4', 'duration': 90000.0})
          : null,
    );
    await FakeSupabase.init();
  });

  setUp(() async {
    FakeSupabase.reset();
    await SessionManager.instance.setSession(
      jwtWithExp(nowSec() + 3600),
      const AuthUser(
        id: 'u1',
        username: 'me',
        nickname: '나',
        userType: 'no_pet',
      ),
      refresh: 'r1',
    );
  });

  testWidgets('60초를 넘는 영상을 고르면 이유를 알려 준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const ChatRoomScreen(
          room: ChatRoomSummary(
            id: 'r1',
            otherNickname: '상대',
            otherUserId: 'u2',
            lastMessage: '',
            lastMessageAt: null,
            unreadCount: 0,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동영상'));
    await tester.pumpAndSettle();

    expect(find.textContaining('동영상은 60초 이하만 첨부할 수 있어요'), findsOneWidget);
    // 서버로는 아무것도 올리지 않는다.
    expect(
      FakeSupabase.requests.where((r) => r.url.path.contains('/storage/')),
      isEmpty,
    );
  });
}
