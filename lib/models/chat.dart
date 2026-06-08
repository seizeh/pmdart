/// 채팅 도메인 모델 (Supabase 실데이터).
library;

DateTime _date(dynamic v) =>
    v == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.parse(v as String).toLocal();

/// 채팅방 목록 항목 (v_chat_rooms 뷰).
class ChatRoomSummary {
  final String id;
  final String otherNickname;
  final String? otherUserId;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const ChatRoomSummary({
    required this.id,
    required this.otherNickname,
    required this.otherUserId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  factory ChatRoomSummary.fromJson(Map<String, dynamic> j) => ChatRoomSummary(
        id: j['id'] as String,
        otherNickname: (j['other_nickname'] ?? '알 수 없음') as String,
        otherUserId: j['other_user_id'] as String?,
        lastMessage: (j['last_message_preview'] ?? '') as String,
        lastMessageAt: j['last_message_at'] == null
            ? null
            : DateTime.parse(j['last_message_at'] as String).toLocal(),
        unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
      );
}

/// 채팅 메시지 (chat_messages).
class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool mine;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.mine,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j, String myId) =>
      ChatMessage(
        id: j['id'] as String,
        roomId: (j['room_id'] ?? '') as String,
        senderId: (j['sender_id'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        createdAt: _date(j['created_at']),
        mine: j['sender_id'] == myId,
      );
}
