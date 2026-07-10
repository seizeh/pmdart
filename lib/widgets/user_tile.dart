import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../models/social.dart';
import '../screen/user_profile_screen.dart';

/// 사용자 한 명을 표시하는 공통 타일 — 프로필 사진 블러 배경 + 중앙 닉네임
/// (채팅 목록과 동일한 프로스트 문법). 채팅·팔로우 동작은 프로필 상세에서.
/// 연결 목록 / 사용자 검색에서 재사용.
class UserTile extends StatelessWidget {
  final Connection connection;

  /// 탭 동작 재정의(선택) — 검색 탭이 타일 자리에서 펼쳐지는 전환을 걸 때 사용.
  /// null 이면 기본(표준 라우트로 프로필 이동).
  final VoidCallback? onTap;

  const UserTile({super.key, required this.connection, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = connection;
    final photo = c.profileImageUrl;
    return Pressable(
      onTap: onTap ??
          () => Navigator.push(
                context,
                AppPageRoute(
                  builder: (_) => UserProfileScreen(
                      userId: c.userId, previewNickname: c.nickname),
                ),
              ),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            // 프로필 사진을 타일 전체 블러 배경으로 — 채팅 목록과 동일 문법.
            if (photo != null)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 18,
                    sigmaY: 18,
                    tileMode: ui.TileMode.clamp,
                  ),
                  child: Image.network(
                    photo,
                    fit: BoxFit.cover,
                    cacheWidth: 400, // 블러 배경 — 저해상 디코딩
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (photo != null)
              const Positioned.fill(
                child: ColoredBox(color: Color(0xB3FFFFFF)),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Text(
                c.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
