import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/app_events.dart';
import 'package:pawmate/services/chat_repository.dart';

import '../helpers/fake_supabase.dart';

Map<String, dynamic> room(String id, String nickname, {String? at}) => {
  'id': id,
  'other_nickname': nickname,
  'other_user_id': 'u-$id',
  'last_message_preview': 'msg',
  'last_message_at': at,
  'unread_count': 0,
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeSupabase.init();
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
