import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../data/mock_data.dart';
import '../auth/auth_wall_dialog.dart';
import '../chat_room_screen.dart';

/// 채팅 탭 — 진행 중인 대화 목록.
class ChatTab extends StatelessWidget {
  final bool isGuest;
  const ChatTab({super.key, this.isGuest = false});

  @override
  Widget build(BuildContext context) {
    if (isGuest) return const _GuestChat();

    final rooms = MockData.chatRooms;

    return Scaffold(
      backgroundColor: AppColors.background,
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
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: rooms.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 64,
                  color: AppColors.border,
                ),
                itemBuilder: (_, i) => _ChatRoomTile(room: rooms[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final MockChatRoom room;
  const _ChatRoomTile({required this.room});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatRoomScreen(room: room)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                room.otherNickname.characters.first,
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
                          timeAgo(room.lastAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (room.postTitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      room.postTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    room.lastMessage,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.rectangle,
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

class _GuestChat extends StatelessWidget {
  const _GuestChat();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
