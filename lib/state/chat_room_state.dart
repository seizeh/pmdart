import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat.dart';
import '../services/chat_repository.dart';
import '../services/error_reporter.dart';

/// 채팅방 화면 상태 홀더 — 메시지 목록/전송과 실시간 구독 수명 관리.
/// (#155 세 번째 전환 — 실시간 구독을 갖는 홀더의 선례, docs/architecture-state.md)
///
/// 다이얼로그(삭제/나가기 확인)·토스트·스크롤·전환 모션은 화면이 담당한다.
/// 전송 계열은 실패 시 사용자 문구(String)를 반환하고 성공이면 null.
class ChatRoomState extends ChangeNotifier {
  ChatRoomState({required this.room, this.subscribeRealtime = true})
    : _otherImageUrl = room.otherProfileImageUrl;

  final ChatRoomSummary room;

  /// 테스트/미리보기에서 웹소켓 연결을 차단하기 위한 스위치.
  final bool subscribeRealtime;

  final ChatRepository _repo = ChatRepository.instance;

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;
  String? _otherImageUrl;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  bool get sending => _sending;

  /// 상대 프로필 사진(히어로 헤더용) — 없으면 닉네임 중앙 표시.
  String? get otherImageUrl => _otherImageUrl;

  /// 새 메시지가 목록에 붙었을 때(수신/전송) — 화면이 맨 아래로 스크롤.
  VoidCallback? onNewMessage;

  /// 초기화 — 화면 initState 에서 1회. 이 방을 보는 동안 이 방의
  /// 포그라운드 푸시 배너를 억제(activeRoomId)한다.
  void init() {
    _repo.activeRoomId = room.id;
    _loadOtherProfile();
    _load();
  }

  /// 이 홀더가 이미 폐기됐는지. **await 재개 지점마다 확인해야 한다**(#235).
  ///
  /// 이 화면은 진입 즉시 네트워크를 두 번 타고(메시지 목록·상대 프로필) 전송
  /// 계열도 전부 async 라, 느린 망에서 뒤로가기를 누르면 재개 지점이 dispose
  /// 이후가 된다. 그때 무엇을 하느냐가 문제였다.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    // 다른 방을 위에 쌓은 경우가 아니면 활성 방 해제.
    if (_repo.activeRoomId == room.id) _repo.activeRoomId = null;
    if (_channel != null) _repo.unsubscribe(_channel!);
    super.dispose();
  }

  /// dispose 뒤 알림을 삼킨다.
  ///
  /// 호출부마다 가드하지 않는 이유는 [notifyListeners] 호출이 15곳이 넘어
  /// **하나씩 빠지기 때문**이다. 한 곳에서 막는다.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final msgs = await _repo.fetchMessages(room.id);
      // 여기가 #235 의 핵심 지점이다. 예전엔 이 확인이 없어서:
      //  · dispose() 가 먼저 돌며 **아직 null 인** _channel 을 해제하고,
      //  · 재개된 이 코드가 그 뒤에 구독을 만들어 **주인 없는 채널**이 남았다.
      // 그 채널은 앱 수명 내내 살아서 메시지가 올 때마다 폐기된 홀더에
      // notify 하고(디버그 assert) 보고 있지도 않은 방에 _markRead 를 썼다.
      if (_disposed) return;
      _messages = msgs;
      _loading = false;
      _notify();
      _markRead();
      // reverse:true 리스트라 첫 프레임부터 맨 아래(최신)에 고정 — 스크롤 점프 불필요.
    } catch (e) {
      if (_disposed) return;
      ErrorReporter.userFacing(e, where: 'chat.loadMessages');
      _loading = false;
      _notify();
    }
    // 실시간 구독 (상대 메시지 수신 + 삭제 반영)
    if (!subscribeRealtime || _disposed) return;
    try {
      _channel = _repo.subscribeMessages(
        room.id,
        onIncoming,
        onDeleted: onMessageDeleted,
      );
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'chat.subscribeMessages',
        why: '구독 실패해도 전송·로드는 정상 — 실시간 수신만 빠진다',
      );
    }
  }

  Future<void> _loadOtherProfile() async {
    final uid = room.otherUserId;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('public_profiles')
          .select('profile_image_url')
          .eq('id', uid)
          .maybeSingle();
      if (_disposed) return;
      _otherImageUrl = row?['profile_image_url'] as String?;
      _notify();
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'chat.otherProfile',
        why: '상대 사진 조회 실패 — 닉네임 중앙 표시 헤더로 폴백한다',
      );
    }
  }

  /// 실시간 수신 — 중복 방지 후 추가, 상대 메시지면 읽음 갱신.
  @visibleForTesting
  void onIncoming(ChatMessage msg) {
    if (_messages.any((m) => m.id == msg.id)) return;
    _messages.add(msg);
    _notify();
    if (!msg.mine) _markRead();
    onNewMessage?.call();
  }

  /// 상대(또는 다른 기기의 나)가 삭제한 메시지 — 화면에서도 즉시 제거.
  @visibleForTesting
  void onMessageDeleted(String messageId) {
    _messages.removeWhere((m) => m.id == messageId);
    _notify();
  }

  void _markRead() {
    if (_messages.isEmpty) return;
    _repo.markRead(room.id, _messages.last.id).catchError((Object e) {
      ErrorReporter.ignored(
        e,
        where: 'chat.markRead',
        why: '읽음 커서는 다음 진입·수신 때 다시 올린다(수렴)',
      );
    });
  }

  /// 텍스트 전송. 성공 null, 실패면 사용자 안내 문구.
  Future<String?> send(String text) async {
    if (text.isEmpty || _sending) return null;
    _sending = true;
    _notify();
    try {
      final msg = await _repo.sendMessage(room.id, text);
      _appendMine(msg);
      return null;
    } catch (e) {
      return _sendErrorMessage(e, '메시지 전송에 실패했어요');
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// 사진 메시지 전송(파일 선택은 화면이 담당). 성공 null, 실패면 안내 문구.
  Future<String?> sendImage(XFile file) async {
    if (_sending) return null;
    _sending = true;
    _notify();
    try {
      final msg = await _repo.sendImageMessage(room.id, file);
      _appendMine(msg);
      return null;
    } catch (e) {
      return _sendErrorMessage(e, '사진 전송에 실패했어요');
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// 동영상 메시지 전송(파일 선택은 화면이 담당). 성공 null, 실패면 안내 문구.
  /// 100MB 초과는 업로드 전에 한국어 안내(StateError)로 돌려준다.
  Future<String?> sendVideo(XFile file) async {
    if (_sending) return null;
    _sending = true;
    _notify();
    try {
      final msg = await _repo.sendVideoMessage(room.id, file);
      _appendMine(msg);
      return null;
    } on StateError catch (e) {
      return e.message; // 100MB 초과 등
    } catch (e) {
      return _sendErrorMessage(e, '동영상 전송에 실패했어요');
    } finally {
      _sending = false;
      _notify();
    }
  }

  void _appendMine(ChatMessage msg) {
    if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
    _notify();
    _markRead();
    onNewMessage?.call();
  }

  /// 서버가 한국어 사유를 준 경우(P0001, 예: 나간 방 잠금) 그대로 보여준다.
  String _sendErrorMessage(Object e, String fallback) {
    if (e is PostgrestException && e.code == 'P0001' && e.message.isNotEmpty) {
      return e.message;
    }
    return fallback;
  }

  /// 내 메시지 삭제(소프트, 확인은 화면이 선행). 성공 여부 반환.
  Future<bool> deleteMyMessage(String messageId) async {
    try {
      await _repo.deleteMessage(messageId);
      _messages.removeWhere((m) => m.id == messageId);
      _notify();
      return true;
    } catch (e) {
      ErrorReporter.userFacing(e, where: 'chat.deleteMessage');
      return false;
    }
  }

  /// 채팅방 나가기(확인은 화면이 선행). 성공 여부 반환.
  Future<bool> leaveRoom() async {
    try {
      await _repo.leaveRoom(room.id);
      return true;
    } catch (e) {
      ErrorReporter.userFacing(e, where: 'chat.leaveRoom');
      return false;
    }
  }
}
