import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../models/chat.dart';
import '../services/chat_repository.dart';
import '../services/report_repository.dart';
import '../services/storage_service.dart';
import '../widgets/report_sheet.dart';

/// 채팅방 — 메시지 목록(실데이터) + 전송 + 실시간 수신.
class ChatRoomScreen extends StatefulWidget {
  final ChatRoomSummary room;

  /// 채팅 목록 타일에서 펼쳐지고/아래로 당기면 타일로 축소되는 인터랙션용. null 이면 일반 화면.
  final Rect? originRect;

  /// 축소 시 크로스페이드로 나타날 실제 채팅 타일(목록과 동일 위젯).
  final WidgetBuilder? cardBuilder;

  const ChatRoomScreen({
    super.key,
    required this.room,
    this.originRect,
    this.cardBuilder,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _repo = ChatRepository.instance;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final msgs = await _repo.fetchMessages(widget.room.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _markRead();
      // reverse:true 리스트라 첫 프레임부터 맨 아래(최신)에 고정 — 별도 스크롤 점프 불필요.
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
    // 실시간 구독 (상대 메시지 수신)
    try {
      _channel = _repo.subscribeMessages(widget.room.id, _onIncoming);
    } catch (_) {
      // 실시간 미동작 시에도 전송/로드는 정상.
    }
  }

  void _onIncoming(ChatMessage msg) {
    if (!mounted) return;
    if (_messages.any((m) => m.id == msg.id)) return; // 중복 방지
    setState(() => _messages.add(msg));
    if (!msg.mine) _markRead();
    _scrollToBottom();
  }

  void _markRead() {
    if (_messages.isEmpty) return;
    _repo.markRead(widget.room.id, _messages.last.id).catchError((_) {});
  }

  @override
  void dispose() {
    if (_channel != null) _repo.unsubscribe(_channel!);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await _repo.sendMessage(widget.room.id, text);
      _ctrl.clear();
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
      });
      _markRead();
      _scrollToBottom();
    } catch (e) {
      _toast(_sendErrorMessage(e, '메시지 전송에 실패했어요'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 서버가 한국어 사유를 준 경우(P0001, 예: 나간 방 잠금) 그대로 보여준다.
  String _sendErrorMessage(Object e, String fallback) {
    if (e is PostgrestException && e.code == 'P0001' && e.message.isNotEmpty) {
      return e.message;
    }
    return fallback;
  }

  /// 사진 첨부 — 갤러리에서 선택해 업로드 후 사진 메시지로 전송.
  Future<void> _sendImage() async {
    if (_sending) return;
    final file = await StorageService.instance.pickImage();
    if (file == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final msg = await _repo.sendImageMessage(widget.room.id, file);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
      });
      _markRead();
      _scrollToBottom();
    } catch (e) {
      _toast(_sendErrorMessage(e, '사진 전송에 실패했어요'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 채팅방 나가기 — 확인 후 목록에서 숨기고 방을 닫는다.
  Future<void> _leaveRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text('나가면 채팅 목록에서 사라지고,\n'
            '서로 새 메시지를 보낼 수 없어요.\n'
            '내가 다시 채팅을 시작하면 대화가 이어져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.leaveRoom(widget.room.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _toast('나가기에 실패했어요. 잠시 후 다시 시도해주세요');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 상단 메뉴 — 사용자 신고 / 채팅방 나가기.
  void _openRoomMenu() {
    final otherId = widget.room.otherUserId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (otherId != null)
              ListTile(
                leading:
                    const Icon(Icons.flag_outlined, color: AppColors.danger),
                title: const Text('사용자 신고'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _report(
                    ReportRepository.targetUser,
                    otherId,
                    '사용자',
                    widget.room.otherNickname,
                  );
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.logout_outlined, color: AppColors.danger),
              title: const Text('채팅방 나가기'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _leaveRoom();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 상대 메시지 길게 누르기 — 해당 메시지 신고.
  void _reportMessage(ChatMessage msg) {
    _report(ReportRepository.targetChatMessage, msg.id, '메시지', msg.content);
  }

  Future<void> _report(
    String type,
    String id,
    String label,
    String title,
  ) async {
    final ok = await showReportSheet(
      context,
      targetType: type,
      targetId: id,
      targetLabel: label,
      targetTitle: title,
    );
    if (ok && mounted) _toast('신고가 접수되었어요. 검토 후 조치할게요');
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos =
          _scroll.position.minScrollExtent; // reverse:true → 0.0 이 맨 아래(최신)
      if (animate) {
        _scroll.animateTo(
          pos,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(pos);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.room.otherNickname.isEmpty
        ? '?'
        : widget.room.otherNickname.characters.first;
    // 타일에서 펼쳐지고/아래로 당기면 타일로 축소되는 공통 래퍼(게시글 상세와 동일 언어).
    return CollapsibleView(
      originRect: widget.originRect,
      card: widget.cardBuilder,
      scrollController: _scroll,
      builder: (context, physics) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(widget.room.otherNickname),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: _openRoomMenu,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildMessages(physics)),
            // 상대가 나간 방은 입력을 잠근다(서버도 INSERT 차단).
            if (widget.room.otherLeft)
              const _LockedBar()
            else
              _Composer(
                controller: _ctrl,
                sending: _sending,
                onSend: _send,
                onPickImage: _sendImage,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(ScrollPhysics physics) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          '첫 메시지를 보내보세요',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
      );
    }
    // reverse:true — 최신 메시지를 맨 아래에 두고 그 위치에서 렌더 시작(진입 시 점프 없음).
    // 데이터는 오래된→최신 순이라, 표시 인덱스는 뒤에서부터 읽는다.
    return ListView.builder(
      controller: _scroll,
      physics: physics, // 드래그 중 잠금은 CollapsibleView 가 제공
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: _messages[_messages.length - 1 - i],
        onReport: _reportMessage,
      ),
    );
  }
}

/// 상대가 나간 방의 잠긴 입력줄 — 안내만 표시.
class _LockedBar extends StatelessWidget {
  const _LockedBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block_outlined, size: 15, color: AppColors.textTertiary),
            SizedBox(width: 6),
            Text(
              '상대가 채팅방을 나가 메시지를 보낼 수 없어요',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(
                Icons.add_photo_alternate_outlined,
                color: AppColors.primaryDark,
              ),
              onPressed: sending ? null : onPickImage,
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: '메시지를 입력하세요',
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primaryDark,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnPrimary,
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward,
                        color: AppColors.textOnPrimary,
                      ),
                onPressed: sending ? null : onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// 상대 메시지 길게 누르기 신고 콜백.
  final void Function(ChatMessage) onReport;
  const _MessageBubble({required this.message, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final at = message.createdAt;
    final timeStr =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: GestureDetector(
              onLongPress: mine ? null : () => onReport(message),
              onTap: message.isImage ? () => _openImage(context) : null,
              child: message.isImage ? _imageBody() : _textBody(mine),
            ),
          ),
          if (!mine) ...[
            const SizedBox(width: 6),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 텍스트 버블.
  Widget _textBody(bool mine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? AppColors.primaryDark : AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
        border: Border.all(
          color: mine ? AppColors.primaryDark : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          color: mine ? AppColors.textOnPrimary : AppColors.textPrimary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  /// 사진 메시지 — 버블 배경 없이 라운드 이미지만(카카오식). 탭하면 크게 보기.
  Widget _imageBody() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280),
        child: Image.network(
          message.imageUrl!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Container(
                  width: 200,
                  height: 200,
                  color: AppColors.surfaceMuted,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
          errorBuilder: (_, _, _) => Container(
            width: 200,
            height: 140,
            color: AppColors.surfaceMuted,
            child: const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: AppColors.textTertiary),
            ),
          ),
        ),
      ),
    );
  }

  /// 전체화면 사진 보기 — 핀치 줌, 탭/뒤로가기로 닫기.
  void _openImage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Image.network(message.imageUrl!, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}
