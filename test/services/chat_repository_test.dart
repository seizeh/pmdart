import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pawmate/services/app_events.dart';
import 'package:pawmate/services/chat_repository.dart';
import 'package:pawmate/services/session.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

Map<String, dynamic> room(String id, String nickname, {String? at}) => {
  'id': id,
  'other_nickname': nickname,
  'other_user_id': 'u-$id',
  'last_message_preview': 'msg',
  'last_message_at': at,
  'unread_count': 0,
};

Map<String, dynamic> msgRow(String id, String at) => {
  'id': id,
  'room_id': 'r1',
  'sender_id': 'u2',
  'content': '메시지 $id',
  'created_at': at,
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    await FakeSupabase.init();
    // fetchMessages 는 로그인 사용자(_uid)를 요구한다.
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

  setUp(FakeSupabase.reset);

  group('ChatRepository.fetchRooms', () {
    test('고객센터 방을 최상단으로 올리고 나머지는 서버 순서(최근 메시지순) 유지', () async {
      FakeSupabase.on(
        'v_chat_rooms',
        (_) => [
          room('r1', '멍집사', at: '2026-07-03T00:00:00Z'),
          room('r2', '고객센터', at: '2026-07-02T00:00:00Z'),
          room('r3', '냥집사', at: '2026-07-01T00:00:00Z'),
        ],
      );

      final rooms = await ChatRepository.instance.fetchRooms();

      expect(rooms.map((r) => r.id).toList(), ['r2', 'r1', 'r3']);
      expect(rooms.first.isSupport, isTrue);
    });

    test('뷰를 최근 메시지 내림차순(null 마지막)으로 요청한다', () async {
      FakeSupabase.on('v_chat_rooms', (_) => []);

      await ChatRepository.instance.fetchRooms();

      final req = FakeSupabase.requests.single;
      expect(req.url.path, '/rest/v1/v_chat_rooms');
      expect(
        req.url.queryParameters['order'],
        'last_message_at.desc.nullslast',
      );
    });
  });

  group('ChatRepository.fetchMessages', () {
    test('최신순 한 페이지를 요청해 오래된→최신으로 뒤집어 반환한다(#230)', () async {
      FakeSupabase.on(
        'chat_messages',
        (_) => [
          msgRow('m2', '2026-07-01T00:00:02Z'),
          msgRow('m1', '2026-07-01T00:00:01Z'),
        ],
      );

      final msgs = await ChatRepository.instance.fetchMessages('r1');

      expect(msgs.map((m) => m.id).toList(), ['m1', 'm2']);
      final q = FakeSupabase.requests.single.url.queryParameters;
      expect(q['order'], startsWith('created_at.desc'), reason: '최신부터');
      expect(q['limit'], '${ChatRepository.messagePageSize}');
      expect(q['room_id'], 'eq.r1');
      expect(q['is_deleted'], 'eq.false');
      expect(q.containsKey('created_at'), isFalse, reason: '첫 페이지는 커서 없음');
    });

    test('before 커서는 created_at lt 필터(UTC)로 나간다', () async {
      FakeSupabase.on('chat_messages', (_) => []);
      final before = DateTime.parse('2026-07-01T00:00:01Z').toLocal();

      await ChatRepository.instance.fetchMessages('r1', before: before);

      final q = FakeSupabase.requests.single.url.queryParameters;
      expect(q['created_at'], 'lt.2026-07-01T00:00:01.000Z');
    });
  });

  group('ChatRepository.sendImageMessage — 업로드 후 INSERT 실패 보상(#233)', () {
    test('INSERT 가 거절되면 방금 올린 파일을 삭제하고 예외를 다시 던진다', () async {
      FakeSupabase.on(
        'object/media',
        (req) => req.method == 'DELETE'
            ? <Object>[] // remove() 응답은 삭제된 객체 목록
            : {'Key': 'media/u1/chat/1.jpg'},
      );
      FakeSupabase.on(
        'chat_messages',
        (_) => FakeSupabase.error(400, {
          'message': '상대방이 나간 방이에요',
          'code': 'P0001',
        }),
      );
      final file = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'a.jpg',
        mimeType: 'image/jpeg',
      );

      await expectLater(
        ChatRepository.instance.sendImageMessage('r1', file),
        throwsA(isA<PostgrestException>()),
      );
      await pumpEventQueue(); // unawaited discard 완료 대기

      final removes = FakeSupabase.requests.where(
        (r) => r.method == 'DELETE' && r.url.path.contains('object/media'),
      );
      expect(removes, hasLength(1), reason: '고아 파일 보상 삭제(#233)');
    });

    test('INSERT 성공이면 삭제 요청이 나가지 않는다', () async {
      FakeSupabase.on(
        'object/media',
        (req) => req.method == 'DELETE'
            ? <Object>[] // remove() 응답은 삭제된 객체 목록
            : {'Key': 'media/u1/chat/1.jpg'},
      );
      FakeSupabase.on(
        'chat_messages',
        (_) => msgRow('m1', '2026-07-01T00:00:01Z'),
      );
      final file = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'a.jpg',
        mimeType: 'image/jpeg',
      );

      await ChatRepository.instance.sendImageMessage('r1', file);
      await pumpEventQueue();

      expect(FakeSupabase.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });
  });

  group('ChatRepository.startDirectChat', () {
    test('RPC 로 방 find-or-create 후 방 요약을 읽고 채팅 이벤트를 발행한다', () async {
      FakeSupabase.on('rpc/start_direct_chat', (_) => 'r9');
      FakeSupabase.on('v_chat_rooms', (_) => room('r9', '냥집사'));

      final before = AppEvents.instance.chat.value;
      final summary = await ChatRepository.instance.startDirectChat(
        'u2',
        context: 'business',
      );

      expect(summary.id, 'r9');
      expect(AppEvents.instance.chat.value, before + 1);

      final rpc = FakeSupabase.requests.first;
      expect(rpc.method, 'POST');
      expect(jsonDecode(rpc.body), {'p_other': 'u2', 'p_context': 'business'});

      final fetch = FakeSupabase.requests[1];
      expect(fetch.url.queryParameters['id'], 'eq.r9');
    });
  });
}
