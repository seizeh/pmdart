import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/pet_search.dart';
import '../models/social.dart';
import '../motion/motion.dart';
import '../services/facility_repository.dart';
import '../theme/app_palette.dart';

/// 검색 결과의 사용자/업체 한 명 — **둥근 정사각형** 카드(2열 그리드용).
///
/// 내정보 탭의 프로필 사진 카드와 같은 문법: 사진을 카드 전체 커버로 깔고
/// 하단만 점진 블러(ShaderMask dstIn) + 스크림 위에 이름을 올린다.
/// 사진이 없으면 프로필 상세 헤더와 동일한 primaryDark 배경(UserTile 관례).
class ProfileSquareCard extends StatelessWidget {
  final Connection connection;
  final VoidCallback? onTap;

  /// 카드 곡률 — 내정보 프로필 사진 카드(24)와 동일. CollapseRoute 로 펼칠 때
  /// UserProfileScreen.cardRadius 에 같은 값을 넘겨야 축소 안착이 튀지 않는다.
  static const double radius = 24;

  const ProfileSquareCard({super.key, required this.connection, this.onTap});

  /// 통계가 로드된 개인 얼굴인가 — 연결 목록처럼 미로딩 맥락이면 행을 접는다
  /// (UserTile 과 같은 판정).
  bool get _hasStats =>
      connection.businessName == null &&
      (connection.reviewCount != null ||
          connection.pawingCount != null ||
          connection.pawmateCount != null);

  /// 내정보 프로필 카드의 통계 셀과 동일한 표기(숫자 17·w800 / 라벨 10·흐림).
  Widget _statCol(String label, int value) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$value',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 1),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xCCFFFFFF)),
      ),
    ],
  );

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: const Color(0x4DFFFFFF));

  @override
  Widget build(BuildContext context) {
    final c = connection;
    final photo = c.profileImageUrl;
    final hasPhoto = photo != null;
    final name = c.businessName ?? c.nickname;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.colors.primaryDark,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                Image.network(
                  photo,
                  fit: BoxFit.cover,
                  cacheWidth: 600,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              // 하단 점진 블러 — 내정보 프로필 카드와 동일 문법.
              if (hasPhoto)
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0xFFFFFFFF),
                      ],
                      stops: [0.0, 0.5, 0.88],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 22,
                        sigmaY: 22,
                        tileMode: ui.TileMode.clamp,
                      ),
                      child: Image.network(
                        photo,
                        fit: BoxFit.cover,
                        cacheWidth: 300, // 블러 사본 — 저해상 디코딩으로 충분
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              // 가독용 스크림.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 80,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x4D000000)],
                    ),
                  ),
                ),
              ),
              // 이름 — 사진 없으면 카드 정중앙(단독), 있으면 아래 하단 블록에서.
              if (!hasPhoto)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textOnPrimary,
                      ),
                    ),
                  ),
                ),
              // 하단 정보 블록 — 배지/통계는 사진 유무와 무관하게 같은 자리.
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasPhoto)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            // 스크림 위 — 항상 밝은 글자.
                            color: context.colors.textOnPrimary,
                          ),
                        ),
                      if (c.businessName != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified,
                              size: 11,
                              color: context.colors.textOnPrimary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '인증 업체',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textOnPrimary,
                              ),
                            ),
                          ],
                        ),
                      ] else if (_hasStats) ...[
                        // 내정보 프로필 카드의 통계 행을 그대로 인용 —
                        // 받은 후기 · Pawing · Pawmate (숫자 굵게/라벨 흐리게).
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _statCol('받은 후기', c.reviewCount ?? 0),
                            ),
                            _statDivider(),
                            Expanded(
                              child: _statCol('Pawing', c.pawingCount ?? 0),
                            ),
                            _statDivider(),
                            Expanded(
                              child: _statCol('Pawmate', c.pawmateCount ?? 0),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 검색 결과의 반려동물 한 마리 — 사용자 카드와 같은 둥근 정사각형(2열 그리드).
/// 사진 커버 + 하단 점진 블러 + 이름·(품종 · 보호자) 한 줄. 사진 없으면
/// primaryDark 배경에 발자국 아이콘.
class PetSquareCard extends StatelessWidget {
  final PetHit pet;
  final VoidCallback? onTap;

  const PetSquareCard({super.key, required this.pet, this.onTap});

  @override
  Widget build(BuildContext context) {
    final photo = pet.imageUrl;
    final hasPhoto = photo != null;
    final subtitle = [
      if (pet.species.isNotEmpty) pet.species,
      if (pet.ownerNickname.isNotEmpty) '보호자 ${pet.ownerNickname}',
    ].join(' · ');
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ProfileSquareCard.radius),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.colors.primaryDark,
            borderRadius: BorderRadius.circular(ProfileSquareCard.radius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                Image.network(
                  photo,
                  fit: BoxFit.cover,
                  cacheWidth: 600,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              if (hasPhoto)
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0xFFFFFFFF),
                      ],
                      stops: [0.0, 0.5, 0.88],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 22,
                        sigmaY: 22,
                        tileMode: ui.TileMode.clamp,
                      ),
                      child: Image.network(
                        photo,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 80,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x4D000000)],
                    ),
                  ),
                ),
              ),
              if (!hasPhoto)
                Center(
                  child: Icon(
                    Icons.pets,
                    size: 44,
                    color: context.colors.textOnPrimary.withValues(alpha: 0.25),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textOnPrimary,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: context.colors.textOnPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 미인증 매장(공공데이터 시설) — 프로필 사진이 없는 자리라 같은 둥근 정사각형에
/// 아이콘 얼굴 + 이름/카테고리로 채운다. 탭하면 후기 작성(기존 동선 유지).
class FacilitySquareCard extends StatelessWidget {
  final Facility facility;
  final VoidCallback? onTap;

  const FacilitySquareCard({super.key, required this.facility, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = facility;
    final meta = kFacilityLabels[f.category] ?? f.category;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ProfileSquareCard.radius),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(ProfileSquareCard.radius),
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: c.primarySoft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.storefront_outlined,
                      size: 26,
                      color: c.primaryDark,
                    ),
                  ),
                ),
              ),
              Text(
                f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
