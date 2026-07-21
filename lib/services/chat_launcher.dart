import 'dart:async';

import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../screen/chat_room_screen.dart';
import 'chat_repository.dart';

/// 상대 user_id 로 1:1 채팅방을 열어준다 (find-or-create 후 화면 이동).
/// 게시글 상세 / pawmate 목록 / 사용자 검색 등에서 공통 사용.
/// [business]=true 면 업체 문의 방 — 개인 대화와 별개의 방으로 분리(0025).
Future<void> openDirectChat(
  BuildContext context,
  String otherUserId, {
  bool business = false,
}) async {
  unawaited(
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    final room = await ChatRepository.instance.startDirectChat(
      otherUserId,
      context: business ? 'business' : 'personal',
    );
    if (!context.mounted) return;
    Navigator.pop(context); // 로딩 닫기
    // 프로필 등에서 연 채팅방도 목록에서 연 것과 동일한 언어로 — 아래에서 떠오르고,
    // 헤더(프로필 바)를 잡아 아래로 내리면 닫힌다(가로 스와이프 back 대체).
    Navigator.push(
      context,
      CollapseRoute(
        builder: (_) =>
            ChatRoomScreen(room: room, originRect: riseOriginRect(context)),
      ),
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
