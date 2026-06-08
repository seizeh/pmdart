import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart';

class ChatRoomScreen extends StatefulWidget {
  final MockChatRoom room;
  const ChatRoomScreen({super.key, required this.room});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late List<_Message> _messages;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _messages = [
      _Message('안녕하세요! 게시글 보고 연락드려요', sentByMe: false, at: now.subtract(const Duration(minutes: 25))),
      _Message('안녕하세요~ 반가워요', sentByMe: true, at: now.subtract(const Duration(minutes: 23))),
      _Message('내일 시간 괜찮으세요?', sentByMe: false, at: now.subtract(const Duration(minutes: 20))),
      _Message('네 5시 호수공원 어떠세요?', sentByMe: true, at: now.subtract(const Duration(minutes: 18))),
      _Message('좋아요 그때 뵐게요!', sentByMe: false, at: now.subtract(const Duration(minutes: 12))),
    ];
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                widget.room.otherNickname.characters.first,
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
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(message: _messages[i]),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                    top: BorderSide(color: AppColors.border, width: 0.5)),
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
                        controller: _ctrl,
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
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1.2),
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
                      icon: const Icon(Icons.arrow_upward,
                          color: AppColors.textOnPrimary),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Message(text, sentByMe: true, at: DateTime.now()));
      _ctrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }
}

class _Message {
  final String content;
  final bool sentByMe;
  final DateTime at;
  _Message(this.content, {required this.sentByMe, required this.at});
}

class _MessageBubble extends StatelessWidget {
  final _Message message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.sentByMe;
    final at = message.at;
    final timeStr =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
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
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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