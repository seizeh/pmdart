import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/chat.dart';
import 'package:pawmate/services/chat_repository.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/state/chat_room_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'no_pet',
);

const _room = ChatRoomSummary(
  id: 'r1',
  otherNickname: '냥집사',
  otherUserId: 'u2',
  lastMessage: '',
  lastMessageAt: null,
  unreadCount: 0,
);

Map<String, dynamic> msg(String id, {String sender = 'u2'}) => {
  'id': id,
  'room_id': 'r1',
  'sender_id': sender,
  'content': '메시지 $id',
  'created_at': '2026-07-01T00:00:00Z',
};

ChatRoomState newState() =>
    ChatRoomState(room: _room, subscribeRealtime: false);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await FakeSupabase.init();
  });

  setUp(() async {
    FakeSupabase.reset();
    SharedPreferences.setMockInitialValues({});
    await SessionManager.instance.setSession(
      jwtWithExp(nowSec() + 3600),
      _me,
      refresh: 'r1',
    );
  });

  group('ChatRoomState.init', () {
    test('메시지를 로드하고 마지막 메시지로 읽음 처리, 활성 방 등록', () async {
      FakeSupabase.on('chat_messages', (_) => [msg('m1'), msg('m2')]);
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();

      s.init();
      await pumpEventQueue();

      expect(ChatRepository.instance.activeRoomId, 'r1', reason: '푸시 배너 억제');
      expect(s.loading, isFalse);
      expect(s.messages.map((m) => m.id), ['m1', 'm2']);
      final read = FakeSupabase.requests.singleWhere(
        (r) => r.url.path.contains('chat_room_members'),
      );
      expect(read.method, 'PATCH');
      expect(jsonDecode(read.body), {'last_read_message_id': 'm2'});

      s.dispose();
      expect(ChatRepository.instance.activeRoomId, isNull, reason: '이탈 시 해제');
    });

    test('빈 방은 읽음 처리 요청을 보내지 않는다', () async {
      FakeSupabase.on('chat_messages', (_) => []);
      final s = newState();

      s.init();
      await pumpEventQueue();

      expect(
        FakeSupabase.requests.map((r) => r.url.path),
        everyElement(isNot(contains('chat_room_members'))),
      );
      s.dispose();
    });
  });

  group('ChatRoomState.onIncoming — 실시간 수신', () {
    test('중복 id 는 한 번만 붙고, 상대 메시지면 읽음 갱신 + 스크롤 콜백', () async {
      FakeSupabase.on('chat_messages', (_) => []);
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();
      var scrolled = 0;
      s.onNewMessage = () => scrolled++;
      final incoming = ChatMessage.fromJson(msg('m9'), 'u1');

      s.onIncoming(incoming);
      s.onIncoming(incoming); // 중복

      expect(s.messages, hasLength(1));
      expect(scrolled, 1);
      await pumpEventQueue();
      expect(
        FakeSupabase.requests.where(
          (r) => r.url.path.contains('chat_room_members'),
        ),
        hasLength(1),
        reason: '상대 메시지 수신 → 읽음 갱신',
      );
      s.dispose();
    });

    test('삭제 이벤트는 해당 메시지를 즉시 제거한다', () {
      final s = newState();
      s.onIncoming(ChatMessage.fromJson(msg('m1'), 'u1'));
      s.onIncoming(ChatMessage.fromJson(msg('m2'), 'u1'));

      s.onMessageDeleted('m1');

      expect(s.messages.map((m) => m.id), ['m2']);
      s.dispose();
    });
  });

  group('ChatRoomState.send', () {
    test('성공: 목록에 붙고 null 반환, sending 수명 정상', () async {
      FakeSupabase.on('chat_messages', (req) => msg('m1', sender: 'u1'));
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();

      final future = s.send('안녕');
      expect(s.sending, isTrue);
      final err = await future;

      expect(err, isNull);
      expect(s.sending, isFalse);
      expect(s.messages.single.mine, isTrue);
    });

    test('서버가 P0001 한국어 사유를 주면 그대로 반환한다(나간 방 잠금 등)', () async {
      FakeSupabase.on(
        'chat_messages',
        (_) => FakeSupabase.error(400, {
          'message': '상대방이 나간 방이에요',
          'code': 'P0001',
        }),
      );
      final s = newState();

      expect(await s.send('안녕'), '상대방이 나간 방이에요');
      expect(s.messages, isEmpty);
    });

    test('그 외 오류는 일반 안내 문구', () async {
      FakeSupabase.on('chat_messages', (_) => throw Exception('네트워크'));
      final s = newState();

      expect(await s.send('안녕'), '메시지 전송에 실패했어요');
    });
  });

  group('삭제·나가기', () {
    test('deleteMyMessage 성공 시 RPC 호출 + 목록에서 제거', () async {
      FakeSupabase.on('delete_my_chat_message', (_) => null);
      final s = newState();
      s.onIncoming(ChatMessage.fromJson(msg('m1', sender: 'u1'), 'u1'));

      expect(await s.deleteMyMessage('m1'), isTrue);
      expect(s.messages, isEmpty);
      final rpc = FakeSupabase.requests.single;
      expect(jsonDecode(rpc.body), {'p_message': 'm1'});
    });

    test('leaveRoom 은 RPC 성공 여부를 그대로 반환한다', () async {
      FakeSupabase.on('leave_chat_room', (_) => null);
      final s = newState();
      expect(await s.leaveRoom(), isTrue);

      FakeSupabase.on(
        'leave_chat_room',
        (_) => FakeSupabase.error(403, {'message': 'forbidden'}),
      );
      expect(await s.leaveRoom(), isFalse);
    });
  });
}
