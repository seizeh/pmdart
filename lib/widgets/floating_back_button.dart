import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_palette.dart';

/// AppBar 없는 몰입형 화면의 떠 있는 뒤로가기 — 셀로판지 필름 원형 버튼.
/// 콘텐츠가 밑으로 스크롤되며 비쳐 보인다.
class FloatingBackButton extends StatelessWidget {
  const FloatingBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => Navigator.of(context).maybePop(),
      borderRadius: BorderRadius.circular(100),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.colors.frostFilm,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.arrow_back_ios_new,
          size: 18,
          color: context.colors.primaryDark,
        ),
      ),
    );
  }
}
