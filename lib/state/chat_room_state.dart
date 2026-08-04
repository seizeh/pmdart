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
  ChatRoomState({
    required this.room,
    this.subscribeRealtime = true,
    ChatRepository? chat,
  }) : _otherImageUrl = room.otherProfileImageUrl,
       _repo = chat ?? ChatRepository.instance;

  /// 의존은 **선택적 생성자 주입**이다 — 인자를 안 주면 종전대로 싱글턴을 쓴다.
  /// (기존 호출부는 그대로 두고, 테스트만 대역을 넣을 수 있게 하는 점진적 전환.
  ///  NotificationsState 가 먼저 쓰던 방식을 넓혔다.)
  final ChatRepository _repo;

  final ChatRoomSummary room;

  /// 테스트/미리보기에서 웹소켓 연결을 차단하기 위한 스위치.
  final bool subscribeRealtime;

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _disposed = false;
  RealtimeChannel? _channel;
  String? _otherImageUrl;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  bool get sending => _sending;

  /// 위로 스크롤하면 불러올 이전 메시지가 남아 있는지.
  bool get hasMore => _hasMore;

  /// 이전 페이지 로드 중 — 화면이 목록 상단에 스피너를 띄운다.
  bool get loadingOlder => _loadingOlder;

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

  /// 실시간 채널 보유 여부 — dispose 경합 테스트용(#235).
  @visibleForTesting
  bool get hasRealtimeChannel => _channel != null;

  @override
  void dispose() {
    _disposed = true;
    // 다른 방을 위에 쌓은 경우가 아니면 활성 방 해제.
    if (_repo.activeRoomId == room.id) _repo.activeRoomId = null;
    if (_channel != null) _repo.unsubscribe(_channel!);
    super.dispose();
  }

  /// dispose 이후 도착한 비동기 완료가 assert 를 밟지 않게 하는 안전 notify.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    try {
      _messages = await _repo.fetchMessages(room.id);
      if (_disposed) return; // 로딩 중 화면 이탈 — 아래 구독 생성도 막는다(#235)
      _hasMore = _messages.length >= ChatRepository.messagePageSize;
      _loading = false;
      _notify();
      _markRead();
      // reverse:true 리스트라 첫 프레임부터 맨 아래(최신)에 고정 — 스크롤 점프 불필요.
    } catch (e) {
      if (_disposed) return; // 실패 재개 지점도 성공 경로와 같은 가드(#235)
      ErrorReporter.userFacing(e, where: 'chat.loadMessages');
      _loading = false;
      _notify();
    }
    // 실시간 구독 (상대 메시지 수신 + 삭제 반영) — dispose 이후 재개된 경우
    // 구독을 만들면 주인 없는 채널이 앱 수명 내내 남는다(#235).
    if (_disposed || !subscribeRealtime) return;
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

  /// 위로 스크롤 시 이전 페이지 로드 — 오래된 메시지를 목록 앞에 붙인다.
  /// 읽음 커서는 건드리지 않는다(항상 최신 메시지 기준). 실패는 조용히 넘기고
  /// 다음 스크롤에서 재시도한다.
  Future<void> loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    _loadingOlder = true;
    _notify();
    try {
      final older = await _repo.fetchMessages(
        room.id,
        before: _messages.first.createdAt,
      );
      if (_disposed) return;
      _hasMore = older.length >= ChatRepository.messagePageSize;
      final ids = _messages.map((m) => m.id).toSet();
      final added = older.where((m) => !ids.contains(m.id)).toList();
      // 전부 중복이면 커서(_messages.first)가 전진하지 못해 다음 스크롤에
      // 같은 쿼리가 무한 반복된다 — 멈추는 게 안전하다.
      if (added.isEmpty) _hasMore = false;
      _messages.insertAll(0, added);
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'chat.loadOlder',
        why: '다음 스크롤에서 재시도한다 — 현재 목록은 그대로 유효',
      );
    } finally {
      _loadingOlder = false;
      _notify();
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

  // _messages.last 가 항상 최신이라는 전제(초기 로드=최신 페이지, 이전 페이지는
  // 앞에 붙음)로 읽음 커서를 올린다 — 오래된 메시지로 커서를 되돌리면 안 된다(#230).
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
