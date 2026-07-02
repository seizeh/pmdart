import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../screen/chat_room_screen.dart';
import 'chat_repository.dart';

/// 상대 user_id 로 1:1 채팅방을 열어준다 (find-or-create 후 화면 이동).
/// 게시글 상세 / pawmate 목록 / 사용자 검색 등에서 공통 사용.
Future<void> openDirectChat(BuildContext context, String otherUserId) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final room = await ChatRepository.instance.startDirectChat(otherUserId);
    if (!context.mounted) return;
    Navigator.pop(context); // 로딩 닫기
    Navigator.push(
      context,
      AppPageRoute(builder: (_) => ChatRoomScreen(room: room)),
    );
  } catch (_) {
    if (!context.mounted) return;
    Navigator.pop(context); // 로딩 닫기
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('채팅방을 열 수 없어요'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
