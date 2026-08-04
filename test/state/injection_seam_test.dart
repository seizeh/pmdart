import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/chat.dart';
import 'package:pawmate/services/chat_repository.dart';
import 'package:pawmate/state/chat_room_state.dart';

/// 상태 홀더의 **선택적 생성자 주입이 실제로 동작하는가.**
///
/// 이 테스트가 필요한 이유: 주입 자리는 `NotificationsState` 에 이미 있었지만
/// **어느 테스트도 그것을 쓰지 않았다.** 아무도 안 쓰는 주입 자리는 있으나 마나이고,
/// 다음 사람이 쓰려는 순간에야 "사실은 안 됐다" 를 알게 된다(리포지토리 생성자가
/// private 이라 `extends` 가 막히는 등 — 여기서 `implements` + `noSuchMethod` 로
/// 대역을 만들 수 있음을 함께 못 박는다).
///
/// 홀더 하나로 대표해 검증한다. 주입 방식이 같으므로 이게 되면 나머지도 된다.
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository(this.messages);

  final List<ChatMessage> messages;
  int fetchCalls = 0;
  String? lastRoomId;
  String? readUpTo;

  @override
  String? activeRoomId;

  @override
  Future<List<ChatMessage>> fetchMessages(
    String roomId, {
    DateTime? before,
    int limit = ChatRepository.messagePageSize,
  }) async {
    fetchCalls++;
    lastRoomId = roomId;
    return messages;
  }

  @override
  Future<void> markRead(String roomId, String lastMessageId) async {
    readUpTo = lastMessageId;
  }

  // 나머지 멤버는 이 테스트에서 쓰지 않는다. noSuchMethod 를 두면 부분 구현이
  // 허용된다 — 대역이 리포지토리 전체를 흉내 낼 필요가 없다.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChatRoomSummary _room() => const ChatRoomSummary(
  id: 'room-1',
  otherUserId: 'u2',
  otherNickname: '상대',
  lastMessage: '',
  lastMessageAt: null,
  unreadCount: 0,
);

ChatMessage _msg(String id) => ChatMessage(
  id: id,
  roomId: 'room-1',
  senderId: 'u2',
  content: '메시지 $id',
  createdAt: DateTime(2026, 8, 5),
  mine: false,
);

void main() {
  test('주입한 리포지토리를 실제로 쓴다 — 싱글턴으로 새지 않는다', () async {
    final fake = _FakeChatRepository([_msg('m1'), _msg('m2')]);

    // subscribeRealtime: false — 웹소켓을 열지 않는다(테스트에서 붙을 서버가 없다).
    final state = ChatRoomState(
      room: _room(),
      subscribeRealtime: false,
      chat: fake,
    );
    state.init();
    await Future<void>.delayed(Duration.zero); // init 은 비동기 로드를 띄운다

    expect(fake.fetchCalls, 1, reason: '주입한 대역이 호출돼야 한다');
    expect(fake.lastRoomId, 'room-1');
    expect(state.messages.map((m) => m.id), ['m1', 'm2']);
    expect(fake.readUpTo, 'm2', reason: '읽음 처리도 대역으로 간다');
    state.dispose();
  });

  test('인자를 안 주면 종전대로 싱글턴을 쓴다 — 기존 호출부가 안 깨진다', () {
    // 이 경로는 네트워크를 타므로 load() 는 부르지 않는다. 여기서 확인할 것은
    // "주입을 추가했다고 기본 생성이 막히지는 않는다" 이다.
    final state = ChatRoomState(room: _room(), subscribeRealtime: false);
    expect(state.messages, isEmpty);
    state.dispose();
  });
}
