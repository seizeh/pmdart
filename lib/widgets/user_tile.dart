import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_palette.dart';
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

  /// '인증 업체' 배지 한 줄 — 업체 얼굴 표시용, 개인 얼굴은 같은 위젯을
  /// Opacity 0 으로 두어 타일 높이를 통일한다.
  Widget _badgeRow(BuildContext context, bool hasPhoto) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.verified,
        size: 12,
        color: hasPhoto
            ? context.colors.primaryDark
            : context.colors.textOnPrimary,
      ),
      const SizedBox(width: 3),
      Text(
        '인증 업체',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: hasPhoto
              ? context.colors.textSecondary
              : context.colors.textOnPrimary,
        ),
      ),
    ],
  );

  /// 개인 얼굴 통계 한 줄(받은 후기·Pawing·Pawmate). 통계 미로딩(친구 목록 등)
  /// 이면 배지와 같은 위젯을 Opacity 0 으로 두어 높이를 통일한다.
  Widget _statLine(BuildContext context, bool hasPhoto) {
    final c = connection;
    if (c.reviewCount == null && c.pawingCount == null && c.pawmateCount == null) {
      return Opacity(opacity: 0, child: _badgeRow(context, hasPhoto));
    }
    final sub = hasPhoto
        ? context.colors.textSecondary
        : context.colors.textOnPrimary;
    final strong = hasPhoto
        ? context.colors.textPrimary
        : context.colors.textOnPrimary;
    Widget stat(String label, int v) => RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$v ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: strong,
            ),
          ),
          TextSpan(
            text: label,
            style: TextStyle(fontSize: 11, color: sub),
          ),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        stat('후기', c.reviewCount ?? 0),
        const SizedBox(width: 8),
        stat('Pawing', c.pawingCount ?? 0),
        const SizedBox(width: 8),
        stat('Pawmate', c.pawmateCount ?? 0),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = connection;
    final photo = c.profileImageUrl;
    // 사진 없는 사용자는 프로필 상세 헤더와 동일한 primaryDark 배경으로 —
    // 흰 타일 → 진갈색 프로필로 바뀌던 이질감 제거.
    final hasPhoto = photo != null;
    return Pressable(
      onTap:
          onTap ??
          () => Navigator.push(
            context,
            AppPageRoute(
              builder: (_) => UserProfileScreen(
                userId: c.userId,
                previewNickname: c.businessName ?? c.nickname,
                // 상호가 없는 항목은 개인 맥락 — 상대가 업체 모드여도 개인 얼굴만
                // (어떤 사용자가 어떤 업체를 운영하는지 연결 차단, 0025)
                forcePersonalFace: c.businessName == null,
              ),
            ),
          ),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hasPhoto ? null : context.colors.primaryDark,
          borderRadius: BorderRadius.circular(16),
        ),
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
              Positioned.fill(
                child: ColoredBox(color: context.colors.photoVeil),
              ),
            Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // 업체 모드 계정은 상호가 이름 자리에 (0025 프로필 분리)
                    c.businessName ?? c.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: hasPhoto
                          ? context.colors.textPrimary
                          : context.colors.textOnPrimary,
                    ),
                  ),
                  // 이름 아래 한 줄: 업체 얼굴은 '인증 업체' 배지, 개인 얼굴은
                  // 통계(받은 후기·Pawing·Pawmate). 자리를 항상 유지해 개인/업체
                  // 타일 높이가 언제나(폰트 배율 무관) 동일하다.
                  const SizedBox(height: 3),
                  if (c.businessName != null)
                    _badgeRow(context, hasPhoto)
                  else
                    // 개인 얼굴 — 검색 맥락(통계 로드됨)이면 지표, 아니면 빈 자리.
                    _statLine(context, hasPhoto),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
