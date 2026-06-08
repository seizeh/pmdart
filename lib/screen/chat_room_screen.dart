import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../models/chat.dart';
import '../services/chat_repository.dart';

/// 채팅방 — 메시지 목록(실데이터) + 전송 + 실시간 수신.
class ChatRoomScreen extends StatefulWidget {
  final ChatRoomSummary room;
  const ChatRoomScreen({super.key, required this.room});

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
      _scrollToBottom(animate: false);
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

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(pos,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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
    return Scaffold(
      backgroundColor: AppColors.background,
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
          IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _Composer(controller: _ctrl, sending: _sending, onSend: _send),
        ],
      ),
    );
  }

  Widget _buildMessages() {
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
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(message: _messages[i]),
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
              icon: const Icon(Icons.add_photo_alternate_outlined,
                  color: AppColors.primaryDark),
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
                        horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide:
                          const BorderSide(color: AppColors.primary, width: 1.2),
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
                    : const Icon(Icons.arrow_upward,
                        color: AppColors.textOnPrimary),
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
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final at = message.createdAt;
    final timeStr =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Text(timeStr,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textTertiary)),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: Container(
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
            ),
          ),
          if (!mine) ...[
            const SizedBox(width: 6),
            Text(timeStr,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textTertiary)),
          ],
        ],
      ),
    );
  }
}
