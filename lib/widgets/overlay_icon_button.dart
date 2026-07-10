import 'package:flutter/material.dart';

/// 히어로(사진·블롭) 위에 얹는 반투명 원형 앱바 버튼 — 밝은 배경에서도 보이도록
/// 스크림 처리. 게시글 상세·채팅방 등 히어로 헤더 화면들이 공용으로 쓴다.
class OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;
  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.black.withValues(alpha: 0.32),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(icon, color: color),
            tooltip: tooltip,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
