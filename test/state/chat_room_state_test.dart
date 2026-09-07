import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/chat.dart';
import 'package:pawmate/services/app_events.dart';
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

Map<String, dynamic> msg(
  String id, {
  String sender = 'u2',
  String at = '2026-07-01T00:00:00Z',
}) => {
  'id': id,
  'room_id': 'r1',
  'sender_id': sender,
  'content': '메시지 $id',
  'created_at': at,
};

/// 서버 응답 흉내 — [from]번부터 [count]건을 최신순(내림차순)으로.
/// id 는 m<번호>, 번호가 클수록 최신이며 created_at 도 번호에 비례한다.
List<Map<String, dynamic>> descPage(int from, int count) => [
  for (var i = from; i > from - count; i--)
    msg(
      'm$i',
      at:
          '2026-07-01T'
          '${(i ~/ 3600).toString().padLeft(2, '0')}:'
          '${((i ~/ 60) % 60).toString().padLeft(2, '0')}:'
          '${(i % 60).toString().padLeft(2, '0')}Z',
    ),
];

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
    test('메시지를 로드하고(서버 최신순 → 화면 오래된순) 최신 메시지로 읽음 처리, 활성 방 등록', () async {
      // 서버는 최신순으로 응답한다(#230 방향 수정) — 화면 목록은 오래된→최신.
      FakeSupabase.on('chat_messages', (_) => [msg('m2'), msg('m1')]);
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();

      s.init();
      await pumpEventQueue();

      expect(ChatRepository.instance.activeRoomId, 'r1', reason: '푸시 배너 억제');
      expect(s.loading, isFalse);
      expect(s.messages.map((m) => m.id), ['m1', 'm2']);
      expect(s.hasMore, isFalse, reason: '페이지 크기 미만 = 이전 기록 없음');
      final read = FakeSupabase.requests.singleWhere(
        (r) => r.url.path.contains('chat_room_members'),
      );
      expect(read.method, 'PATCH');
      expect(jsonDecode(read.body), {'last_read_message_id': 'm2'});

      s.dispose();
      expect(ChatRepository.instance.activeRoomId, isNull, reason: '이탈 시 해제');
    });

    test('읽음 처리 성공은 방 목록 갱신 이벤트를 쏜다', () async {
      // 목록에서 연 방은 pop 복귀 시 재조회가 따로 있지만, **알림 딥링크로 연
      // 방**은 이 이벤트가 유일한 배지 갱신 경로다 — 없으면 채팅 목록에 미읽음
      // "1" 이 남는다(실사고).
      FakeSupabase.on('chat_messages', (_) => [msg('m1')]);
      FakeSupabase.on('chat_room_members', (_) => []);
      final before = AppEvents.instance.chat.value;
      final s = newState();

      s.init();
      await pumpEventQueue();

      expect(AppEvents.instance.chat.value, greaterThan(before));
      s.dispose();
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

  group('ChatRoomState — dispose 경합(#235)', () {
    test('첫 로딩이 끝나기 전에 dispose 되면 실시간 구독을 만들지 않는다', () async {
      final gate = Completer<void>();
      FakeSupabase.on(
        'chat_messages',
        (_) => gate.future.then((_) => <Map<String, dynamic>>[]),
      );
      // 실제 구독 경로(subscribeRealtime 기본 true)로 가드를 검증한다.
      final s = ChatRoomState(room: _room);

      s.init();
      s.dispose(); // 느린 네트워크에서 진입 직후 뒤로가기
      gate.complete();
      await pumpEventQueue();

      expect(s.hasRealtimeChannel, isFalse, reason: '주인 없는 채널 누수 방지');
    });

    test('dispose 이후 완료된 로드가 notifyListeners assert 를 밟지 않는다', () async {
      final gate = Completer<void>();
      FakeSupabase.on(
        'chat_messages',
        (_) => gate.future.then((_) => [msg('m1')]),
      );
      final s = newState();

      s.init();
      s.dispose();
      gate.complete();
      await pumpEventQueue(); // 가드가 없으면 여기서 disposed notify assert
    });

    test('fetch 완료 전 dispose 하면 읽음 처리를 서버로 보내지 않는다', () async {
      FakeSupabase.on('chat_messages', (_) => [msg('m2'), msg('m1')]);
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();

      s.init();
      s.dispose(); // fetch 가 아직 진행 중
      await pumpEventQueue();

      expect(
        FakeSupabase.requests.map((r) => r.url.path),
        everyElement(isNot(contains('chat_room_members'))),
        reason: '떠난 방에 읽음 커서를 쓰면 안 된다',
      );
    });

    test('로드 실패가 dispose 뒤에 도착해도 예외가 나지 않는다', () async {
      // 성공 경로만 막으면 catch 쪽 재개 지점이 그대로 남는다.
      FakeSupabase.on('chat_messages', (_) => FakeSupabase.error(500, {}));
      final s = newState();

      s.init();
      s.dispose();

      await expectLater(pumpEventQueue(), completes);
    });
  });

  group('ChatRoomState.loadOlder — 이전 페이지', () {
    test('가득 찬 첫 페이지 → hasMore, loadOlder 는 앞에 붙이고 읽음 커서는 안 건드린다', () async {
      // 첫 요청(커서 없음)엔 최신 50건, 커서(lt) 요청엔 그 이전 20건.
      FakeSupabase.on(
        'chat_messages',
        (req) =>
            req.url.queryParameters['created_at']?.startsWith('lt.') == true
            ? descPage(50, 20)
            : descPage(100, 50),
      );
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();

      s.init();
      await pumpEventQueue();
      expect(s.hasMore, isTrue, reason: '가득 찬 페이지 = 이전 기록 있을 수 있음');
      expect(s.messages.first.id, 'm51');
      expect(s.messages.last.id, 'm100', reason: '최신이 마지막');

      await s.loadOlder();

      expect(s.messages, hasLength(70));
      expect(s.messages.first.id, 'm31', reason: '이전 페이지가 앞에 붙는다');
      expect(s.messages.last.id, 'm100', reason: '최신은 그대로');
      expect(s.hasMore, isFalse, reason: '모자란 페이지 = 끝');
      expect(
        FakeSupabase.requests.where(
          (r) => r.url.path.contains('chat_room_members'),
        ),
        hasLength(1),
        reason: '읽음 갱신은 초기 로드의 최신 메시지 1회뿐 — 커서 후퇴 금지(#230)',
      );
      s.dispose();
    });

    test('이전 페이지가 전부 중복이면 hasMore 를 내려 무한 재요청을 막는다', () async {
      // 커서가 전진하지 못하는 병리적 응답 — lt 의미상 정상 경로에선 없지만,
      // 생기면 스크롤마다 같은 쿼리가 반복되므로 멈추는 게 안전하다.
      FakeSupabase.on('chat_messages', (_) => descPage(100, 50));
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();
      s.init();
      await pumpEventQueue();
      expect(s.hasMore, isTrue);

      await s.loadOlder(); // 커서 요청에도 같은 50건이 돌아온다(전부 중복)

      expect(s.messages, hasLength(50));
      expect(s.hasMore, isFalse, reason: '커서가 안 움직였으면 멈춘다');
      s.dispose();
    });

    test('이전 기록이 없으면(짧은 첫 페이지) loadOlder 는 아무 요청도 안 한다', () async {
      FakeSupabase.on('chat_messages', (_) => descPage(3, 3));
      FakeSupabase.on('chat_room_members', (_) => []);
      final s = newState();
      s.init();
      await pumpEventQueue();
      final requestsBefore = FakeSupabase.requests.length;

      await s.loadOlder();

      expect(FakeSupabase.requests.length, requestsBefore);
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
