import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../data/mock_data.dart' show timeAgo;
import '../../models/chat.dart';
import '../../services/chat_repository.dart';
import '../../services/app_events.dart';
import '../auth/auth_wall_dialog.dart';
import '../chat_room_screen.dart';

/// 채팅 탭 — 진행 중인 대화 목록(실데이터).
class ChatTab extends StatefulWidget {
  final bool isGuest;
  const ChatTab({super.key, this.isGuest = false});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _repo = ChatRepository.instance;
  List<ChatRoomSummary> _rooms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _load();
      AppEvents.instance.chat.addListener(_onChatChanged);
    }
  }

  @override
  void dispose() {
    AppEvents.instance.chat.removeListener(_onChatChanged);
    super.dispose();
  }

  void _onChatChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rooms = await _repo.fetchRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_rooms.isEmpty) _error = '채팅을 불러오지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) return const _GuestChat();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '채팅',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(message: _error!, onRetry: _load);
    }
    if (_rooms.isEmpty) {
      return const _MessageState(
        message: '아직 진행 중인 대화가 없어요.\n게시글에서 상대에게 채팅을 시작해보세요!',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _rooms.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          indent: 64,
          color: AppColors.border,
        ),
        itemBuilder: (_, i) => _ChatRoomTile(
          room: _rooms[i],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatRoomScreen(room: _rooms[i])),
            );
            _load(silent: true); // 읽음/새 메시지 반영
          },
        ),
      ),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final ChatRoomSummary room;
  final VoidCallback onTap;
  const _ChatRoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial =
        room.otherNickname.isEmpty ? '?' : room.otherNickname.characters.first;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        room.otherNickname,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          room.lastMessageAt == null
                              ? ''
                              : timeAgo(room.lastMessageAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    room.lastMessage.isEmpty ? '대화를 시작해보세요' : room.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (room.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.all(Radius.circular(100)),
                ),
                child: Text(
                  '${room.unreadCount}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _MessageState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuestChat extends StatelessWidget {
  const _GuestChat();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(Icons.chat_bubble_outline,
                      size: 48, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 20),
                const Text(
                  '채팅은 로그인 후 이용할 수 있어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => AuthWallDialog.show(
                    context,
                    message: '채팅은 로그인 후 이용할 수 있어요',
                  ),
                  child: const Text('로그인하러 가기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
