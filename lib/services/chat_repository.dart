import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat.dart';
import 'app_events.dart';
import 'session.dart';

/// 채팅(방 목록 / 메시지 / 전송 / 읽음 / 실시간) 데이터 접근.
class ChatRepository {
  ChatRepository._();
  static final ChatRepository instance = ChatRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String get _uid {
    final id = SessionManager.instance.user?.id;
    if (id == null) throw StateError('로그인이 필요합니다');
    return id;
  }

  /// 상대와의 1:1 채팅방 find-or-create 후 방 요약 반환.
  /// 상대 멤버십 INSERT 는 RLS 로 막히므로 SECURITY DEFINER RPC(start_direct_chat)로 처리.
  Future<ChatRoomSummary> startDirectChat(String otherUserId) async {
    final roomId = await _c
        .rpc('start_direct_chat', params: {'p_other': otherUserId}) as String;
    final row =
        await _c.from('v_chat_rooms').select().eq('id', roomId).single();
    AppEvents.instance.notifyChat();
    return ChatRoomSummary.fromJson(row);
  }

  /// 단일 채팅방 조회 (알림 등에서 이동용). 없으면 null.
  Future<ChatRoomSummary?> fetchRoom(String roomId) async {
    final row =
        await _c.from('v_chat_rooms').select().eq('id', roomId).maybeSingle();
    return row == null ? null : ChatRoomSummary.fromJson(row);
  }

  /// 내 채팅방 목록 (최근 메시지 순).
  Future<List<ChatRoomSummary>> fetchRooms() async {
    final rows = await _c
        .from('v_chat_rooms')
        .select()
        .order('last_message_at', ascending: false, nullsFirst: false);
    return (rows as List)
        .map((r) => ChatRoomSummary.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 방의 메시지 (오래된→최신).
  Future<List<ChatMessage>> fetchMessages(String roomId) async {
    final myId = _uid;
    final rows = await _c
        .from('chat_messages')
        .select('id, room_id, sender_id, content, created_at')
        .eq('room_id', roomId)
        .eq('is_deleted', false)
        .order('created_at', ascending: true)
        .limit(300);
    return (rows as List)
        .map((r) => ChatMessage.fromJson(r as Map<String, dynamic>, myId))
        .toList();
  }

  /// 메시지 전송 — 삽입된 행을 반환.
  Future<ChatMessage> sendMessage(String roomId, String content) async {
    final myId = _uid;
    final row = await _c
        .from('chat_messages')
        .insert({'room_id': roomId, 'sender_id': myId, 'content': content})
        .select('id, room_id, sender_id, content, created_at')
        .single();
    AppEvents.instance.notifyChat();
    return ChatMessage.fromJson(row, myId);
  }

  /// 읽음 처리 — 내 멤버십의 last_read_message_id 갱신.
  Future<void> markRead(String roomId, String lastMessageId) async {
    await _c
        .from('chat_room_members')
        .update({'last_read_message_id': lastMessageId})
        .eq('room_id', roomId)
        .eq('user_id', _uid);
  }

  /// 방의 새 메시지 실시간 구독. 콜백은 새 메시지 1건을 전달.
  RealtimeChannel subscribeMessages(
    String roomId,
    void Function(ChatMessage) onInsert,
  ) {
    final myId = _uid;
    // 커스텀 JWT 를 realtime 인증에 적용 (RLS 통과용).
    _c.realtime.setAuth(SessionManager.instance.token);
    final channel = _c
        .channel('public:chat_messages:room=$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            onInsert(ChatMessage.fromJson(rec, myId));
          },
        )
        .subscribe();
    return channel;
  }

  void unsubscribe(RealtimeChannel channel) {
    _c.removeChannel(channel);
  }
}
