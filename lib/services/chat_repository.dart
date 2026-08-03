import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat.dart';
import 'app_events.dart';
import 'session.dart';
import 'storage_service.dart';

/// 채팅(방 목록 / 메시지 / 전송 / 읽음 / 실시간) 데이터 접근.
class ChatRepository {
  ChatRepository._();
  static final ChatRepository instance = ChatRepository._();

  /// 지금 화면에 열려 있는 채팅방 id — ChatRoomScreen 이 진입/이탈 시 갱신.
  /// 포그라운드 채팅 푸시가 이 방이면 인앱 배너를 생략한다(이미 보고 있음).
  String? activeRoomId;

  SupabaseClient get _c => Supabase.instance.client;
  String get _uid {
    final id = SessionManager.instance.user?.id;
    if (id == null) throw StateError('로그인이 필요합니다');
    return id;
  }

  /// 상대와의 1:1 채팅방 find-or-create 후 방 요약 반환.
  /// 상대 멤버십 INSERT 는 RLS 로 막히므로 SECURITY DEFINER RPC(start_direct_chat)로 처리.
  /// [context]='business' 는 업체 문의 — 같은 상대라도 개인 방과 별개의 방(0025 분리).
  Future<ChatRoomSummary> startDirectChat(
    String otherUserId, {
    String context = 'personal',
  }) async {
    final roomId =
        await _c.rpc(
              'start_direct_chat',
              params: {'p_other': otherUserId, 'p_context': context},
            )
            as String;
    final row = await _c
        .from('v_chat_rooms')
        .select()
        .eq('id', roomId)
        .single();
    AppEvents.instance.notifyChat();
    return ChatRoomSummary.fromJson(row);
  }

  /// 단일 채팅방 조회 (알림 등에서 이동용). 없으면 null.
  Future<ChatRoomSummary?> fetchRoom(String roomId) async {
    final row = await _c
        .from('v_chat_rooms')
        .select()
        .eq('id', roomId)
        .maybeSingle();
    return row == null ? null : ChatRoomSummary.fromJson(row);
  }

  /// 내 채팅방 목록 (고객센터 최상단 고정, 나머지는 최근 메시지 순).
  Future<List<ChatRoomSummary>> fetchRooms() async {
    final rows = await _c
        .from('v_chat_rooms')
        .select()
        .order('last_message_at', ascending: false, nullsFirst: false);
    final rooms = (rows as List)
        .map((r) => ChatRoomSummary.fromJson(r as Map<String, dynamic>))
        .toList();
    return [
      ...rooms.where((r) => r.isSupport),
      ...rooms.where((r) => !r.isSupport),
    ];
  }

  static const _messageCols =
      'id, room_id, sender_id, content, image_url, image_mime_type, '
      'image_thumbnail_url, created_at';

  /// 메시지 페이지 크기 — 첫 로드는 최신 한 페이지, 위로 스크롤 시 한 페이지씩.
  static const messagePageSize = 50;

  /// 방의 메시지 한 페이지 (오래된→최신). 서버에서 최신순으로 [limit]개를
  /// 받아 뒤집는다 — 오름차순 고정 조회는 방이 커지면 오래된 쪽만 보였다(#230).
  /// [before] 가 있으면 그 시각 이전(이전 페이지)을 조회한다.
  Future<List<ChatMessage>> fetchMessages(
    String roomId, {
    DateTime? before,
    int limit = messagePageSize,
  }) async {
    final myId = _uid;
    var query = _c
        .from('chat_messages')
        .select(_messageCols)
        .eq('room_id', roomId)
        .eq('is_deleted', false);
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((r) => ChatMessage.fromJson(r as Map<String, dynamic>, myId))
        .toList()
        .reversed
        .toList();
  }

  /// 메시지 전송 — 삽입된 행을 반환.
  Future<ChatMessage> sendMessage(String roomId, String content) async {
    final myId = _uid;
    final row = await _c
        .from('chat_messages')
        .insert({'room_id': roomId, 'sender_id': myId, 'content': content})
        .select(_messageCols)
        .single();
    AppEvents.instance.notifyChat();
    return ChatMessage.fromJson(row, myId);
  }

  /// 사진 메시지 전송 — media 버킷(chat 카테고리)에 올린 뒤 image_url 로 삽입.
  /// (서버 CHECK: content 또는 image_url 필수, 이미지 10MB 제한.)
  Future<ChatMessage> sendImageMessage(String roomId, XFile file) async {
    final myId = _uid;
    final img = await StorageService.instance.upload(file, category: 'chat');
    final row = await _c
        .from('chat_messages')
        .insert({
          'room_id': roomId,
          'sender_id': myId,
          'image_url': img.url,
          'image_mime_type': img.mime,
          'image_file_size': img.size,
        })
        .select(_messageCols)
        .single();
    AppEvents.instance.notifyChat();
    return ChatMessage.fromJson(row, myId);
  }

  /// 동영상 메시지 전송 — media 버킷(chat)에 영상+포스터를 올린 뒤 삽입.
  /// (단일 미디어 슬롯 재사용: image_url=영상, mime=video/*, thumbnail=포스터.
  /// 방 목록 미리보기 '[동영상]'은 서버 트리거가 처리. 영상 100MB 서버 CHECK.)
  Future<ChatMessage> sendVideoMessage(String roomId, XFile file) async {
    final myId = _uid;
    final video = await StorageService.instance.uploadVideo(
      file,
      category: 'chat',
    );
    final row = await _c
        .from('chat_messages')
        .insert({
          'room_id': roomId,
          'sender_id': myId,
          'image_url': video.url,
          'image_mime_type': video.mime,
          'image_file_size': video.size,
          'image_thumbnail_url': video.thumbUrl,
        })
        .select(_messageCols)
        .single();
    AppEvents.instance.notifyChat();
    return ChatMessage.fromJson(row, myId);
  }

  /// 채팅방 나가기 — 내 목록에서 숨긴다(이력 유지). 상대가 새 메시지를 보내면
  /// 다시 나타난다. 서버 RPC 가 읽음 커서 정리 + left_at 기록을 처리.
  Future<void> leaveRoom(String roomId) async {
    await _c.rpc('leave_chat_room', params: {'p_room': roomId});
    AppEvents.instance.notifyChat();
  }

  /// 읽음 처리 — 내 멤버십의 last_read_message_id 갱신.
  Future<void> markRead(String roomId, String lastMessageId) async {
    await _c
        .from('chat_room_members')
        .update({'last_read_message_id': lastMessageId})
        .eq('room_id', roomId)
        .eq('user_id', _uid);
  }

  /// 내 메시지 삭제(소프트) — 서버 RPC 가 본인 검증·방 미리보기·미읽음 보정까지 처리.
  Future<void> deleteMessage(String messageId) async {
    await _c.rpc('delete_my_chat_message', params: {'p_message': messageId});
    AppEvents.instance.notifyChat(); // 방 목록 미리보기 갱신
  }

  /// 방의 새 메시지 실시간 구독. [onInsert] 는 새 메시지 1건,
  /// [onDeleted] 는 상대가 삭제한 메시지 id(내 화면에서도 즉시 제거용).
  RealtimeChannel subscribeMessages(
    String roomId,
    void Function(ChatMessage) onInsert, {
    void Function(String messageId)? onDeleted,
  }) {
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
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec['is_deleted'] == true) {
              onDeleted?.call(rec['id'] as String);
            }
          },
        )
        .subscribe();
    return channel;
  }

  void unsubscribe(RealtimeChannel channel) {
    _c.removeChannel(channel);
  }
}
