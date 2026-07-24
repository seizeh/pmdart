/// 채팅 도메인 모델 (Supabase 실데이터).
library;

DateTime _date(dynamic v) => v == null
    ? DateTime.fromMillisecondsSinceEpoch(0)
    : DateTime.parse(v as String).toLocal();

/// 채팅방 목록 항목 (v_chat_rooms 뷰).
class ChatRoomSummary {
  final String id;
  final String otherNickname;
  final String? otherUserId;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// 상대가 방을 나갔는지 — true 면 새 메시지를 보낼 수 없다(서버도 차단).
  final bool otherLeft;

  /// 상대 프로필 사진 — 목록 타일 블러 배경·채팅방 헤더에 사용.
  final String? otherProfileImageUrl;

  const ChatRoomSummary({
    required this.id,
    required this.otherNickname,
    required this.otherUserId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    this.otherLeft = false,
    this.otherProfileImageUrl,
    this.context = 'personal',
  });

  /// 방 컨텍스트 — 'business' 면 업체 문의 방(상대가 상호로 표시된다, 0025 분리).
  final String context;
  bool get isBusinessInquiry => context == 'business';

  /// 고객센터(admin_inquiry) 방 여부 — v_chat_rooms 가 상대를 '고객센터'로 표기한다.
  bool get isSupport => otherNickname == '고객센터';

  factory ChatRoomSummary.fromJson(Map<String, dynamic> j) => ChatRoomSummary(
    id: j['id'] as String,
    otherNickname: (j['other_nickname'] ?? '알 수 없음') as String,
    otherUserId: j['other_user_id'] as String?,
    lastMessage: (j['last_message_preview'] ?? '') as String,
    lastMessageAt: j['last_message_at'] == null
        ? null
        : DateTime.parse(j['last_message_at'] as String).toLocal(),
    unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
    otherLeft: j['other_left'] == true,
    otherProfileImageUrl: j['other_profile_image_url'] as String?,
    context: (j['context'] as String?) ?? 'personal',
  );
}

/// 채팅 메시지 (chat_messages). 텍스트 / 사진 / 동영상(image_url 슬롯 재사용,
/// mime 이 video/* 면 image_url 이 영상이고 image_thumbnail_url 이 포스터).
class ChatMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final String? imageUrl;
  final String? imageMime;
  final String? imageThumbUrl; // 영상 포스터(jpeg) — 사진 메시지는 null
  final DateTime createdAt;
  final bool mine;

  bool get isVideo => imageMime?.startsWith('video/') ?? false;
  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty && !isVideo;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    this.imageUrl,
    this.imageMime,
    this.imageThumbUrl,
    required this.createdAt,
    required this.mine,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j, String myId) =>
      ChatMessage(
        id: j['id'] as String,
        roomId: (j['room_id'] ?? '') as String,
        senderId: (j['sender_id'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        imageUrl: j['image_url'] as String?,
        imageMime: j['image_mime_type'] as String?,
        imageThumbUrl: j['image_thumbnail_url'] as String?,
        createdAt: _date(j['created_at']),
        mine: j['sender_id'] == myId,
      );
}
