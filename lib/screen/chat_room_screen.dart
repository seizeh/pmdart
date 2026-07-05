import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../models/chat.dart';
import '../services/chat_repository.dart';
import '../services/report_repository.dart';
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('메시지 전송에 실패했어요'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 상단 메뉴 — 현재는 상대 사용자 신고.
  void _openRoomMenu() {
    final otherId = widget.room.otherUserId;
    if (otherId == null) {
      _toast('상대 정보를 불러오지 못했어요');
      return;
    }
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
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.danger),
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
            _Composer(controller: _ctrl, sending: _sending, onSend: _send),
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

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
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
              onPressed: () {},
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
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
                    color: mine
                        ? AppColors.textOnPrimary
                        : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
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
}
