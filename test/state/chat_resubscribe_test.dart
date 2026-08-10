import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/chat.dart';
import 'package:pawmate/services/chat_repository.dart';
import 'package:pawmate/state/chat_room_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 채팅방 실시간 구독이 끊겼을 때 **정확히 한 번** 되붙는가.
///
/// 이 테스트가 필요한 이유: `unsubscribe()`(→ removeChannel)는 그 채널의 subscribe
/// 콜백에 closed 를 한 번 더 발화시킨다. 소켓이 이미 끊겨 있으면 — 끊김 복구의
/// 대부분이 이 경우다 — realtime_channel 의 `if (!canPush) leavePush.trigger('ok')`
/// 경로를 타 **동기로** 되돌아온다. 세대 가드가 없으면 그 재진입이 재시도를
/// 이중으로 잡아 채널이 하나 새고, 샌 채널의 이후 이벤트가 다시 재구독을 부른다.
///
/// 대역이 그 동기 재발화를 그대로 흉내 낸다 — 이게 없으면 테스트가 버그를 못 잡는다.
class _FakeChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DropRepo implements ChatRepository {
  int subscribeCalls = 0;
  int unsubscribeCalls = 0;

  /// 살아 있는 채널 → 그 채널의 onDropped.
  final _callbacks =
      <Object, void Function(RealtimeSubscribeStatus, Object?)>{};

  int get liveChannels => _callbacks.length;

  @override
  String? activeRoomId;

  @override
  Future<List<ChatMessage>> fetchMessages(
    String roomId, {
    DateTime? before,
    int limit = ChatRepository.messagePageSize,
  }) async => const [];

  @override
  Future<void> markRead(String roomId, String lastMessageId) async {}

  @override
  RealtimeChannel subscribeMessages(
    String roomId,
    void Function(ChatMessage) onInsert, {
    void Function(String messageId)? onDeleted,
    void Function(RealtimeSubscribeStatus status, Object? err)? onDropped,
  }) {
    subscribeCalls++;
    final ch = _FakeChannel();
    if (onDropped != null) _callbacks[ch] = onDropped;
    return ch;
  }

  @override
  void unsubscribe(RealtimeChannel channel) {
    unsubscribeCalls++;
    final cb = _callbacks.remove(channel);
    // 패키지 동작 재현: 소켓이 끊긴 상태면 closed 가 **동기로** 되돌아온다.
    cb?.call(RealtimeSubscribeStatus.closed, null);
  }

  /// 서버가 끊은 상황 — 살아 있는 채널에 closed 를 던진다.
  void dropAll() {
    for (final entry in _callbacks.entries.toList()) {
      entry.value(RealtimeSubscribeStatus.closed, null);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

ChatRoomSummary _room() => const ChatRoomSummary(
  id: 'room-1',
  otherUserId: 'u2',
  otherNickname: '상대',
  lastMessage: '',
  lastMessageAt: null,
  unreadCount: 0,
);

void main() {
  test('끊김 복구 — 재구독은 정확히 한 번, 채널이 새지 않는다', () async {
    final repo = _DropRepo();
    final state = ChatRoomState(room: _room(), chat: repo);
    state.init();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.subscribeCalls, 1, reason: '최초 구독');
    expect(repo.liveChannels, 1);

    repo.dropAll(); // 서버가 끊음 → 백오프 1초 뒤 재구독

    // 2.6초를 기다리는 이유: 이중 예약이 일어나면 두 타이머의 지연이 다르다.
    // 먼저 잡힌 것은 _attempt=0 이라 1초, 나중 것은 _attempt=1 이라 2초 뒤에
    // 발화한다 — 1.4초만 보면 버그가 있어도 1회로 보여 테스트가 통과해 버린다.
    await Future<void>.delayed(const Duration(milliseconds: 2600));

    // 세대 가드가 없으면 동기 재진입이 타이머를 이중으로 잡아 2회가 된다.
    expect(repo.subscribeCalls, 2, reason: '재구독은 한 번뿐이어야 한다');
    expect(repo.liveChannels, 1, reason: '채널이 새면 안 된다');
    expect(state.hasRealtimeChannel, isTrue);

    state.dispose();
  });

  test('재구독 뒤 도착한 죽은 채널의 closed 는 새 채널을 죽이지 않는다', () async {
    final repo = _DropRepo();
    final state = ChatRoomState(room: _room(), chat: repo);
    state.init();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 죽을 채널의 콜백을 손에 쥐고 끊는다.
    final stale = repo._callbacks.entries.first.value;
    repo.dropAll();
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    expect(repo.subscribeCalls, 2);

    // 재구독이 끝난 뒤 옛 채널의 closed 가 뒤늦게 도착.
    stale(RealtimeSubscribeStatus.closed, null);
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    expect(
      repo.subscribeCalls,
      2,
      reason: '뒤늦은 closed 는 무시돼야 한다 — 아니면 30초마다 재구독이 돈다',
    );
    expect(state.hasRealtimeChannel, isTrue);

    state.dispose();
  });
}
