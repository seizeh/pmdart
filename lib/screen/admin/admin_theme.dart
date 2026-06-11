import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 관리자 화면 공용 AppBar — 딥 슬레이트 색으로 일반 화면과 구분.
AppBar adminAppBar(String title,
    {List<Widget>? actions, PreferredSizeWidget? bottom}) {
  return AppBar(
    title: Text(title),
    backgroundColor: AppColors.adminAccent,
    foregroundColor: AppColors.adminOnAccent,
    elevation: 0,
    actions: actions,
    bottom: bottom,
  );
}

/// '관리자' 배지.
class AdminBadge extends StatelessWidget {
  final bool light;
  const AdminBadge({super.key, this.light = false});

  @override
  Widget build(BuildContext context) {
    final bg = light ? Colors.white.withValues(alpha: 0.18) : AppColors.adminAccentSoft;
    final fg = light ? AppColors.adminOnAccent : AppColors.adminAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 12, color: fg),
          const SizedBox(width: 4),
          Text('관리자',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}
