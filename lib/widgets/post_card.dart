import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/community.dart';
import '../motion/motion.dart';
import '../screen/user_profile_screen.dart';
import '../theme/app_palette.dart';
import '../utils/labels.dart' show categoryLabel, timeAgo;
import 'blob_background.dart';
import 'role_badge.dart';

/// 커뮤니티 게시글 카드 — 애플뮤직 아티스트 카드 스타일.
/// 대표사진이 카드 전체를 채우고, 하단은 사진을 이어받아 이음새 없이 점점
/// 뭉개지는 블러 구간에 기존 정보(카테고리·지역·시간·제목·내용·약속·작성자·
/// 하트/댓글/조회)를 올린다. 사진이 없으면 카테고리 색 블롭을 뿌옇게 깐다.
class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;
  final VoidCallback? onHeart;

  const PostCard({super.key, required this.post, this.onTap, this.onHeart});

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(context, post.category);
    // 영상 글은 포스터(썸네일)를 대표 이미지로 쓴다. 포스터가 없으면 어두운
    // 타일 + ▶ 로 폴백(사진 레이아웃 유지 — 본문 히어로 없음).
    final displayUrl = post.isVideo ? post.imageThumbUrl : post.imageUrl;
    final hasPhoto = displayUrl != null || post.isVideo;

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: AspectRatio(
          aspectRatio: kPostImageAspectRatio, // 4284 : 5712
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 배경 — 대표사진(영상은 포스터) 또는 카테고리 색 블롭.
              // 포스터 없는 영상은 어두운 타일.
              if (displayUrl != null)
                Image.network(
                  displayUrl,
                  fit: BoxFit.cover,
                  // 원본(최대 4284px 폭) 풀해상 디코딩 방지 — 카드 폭이면 충분.
                  cacheWidth: 1200,
                  errorBuilder: (_, _, _) => post.isVideo
                      ? const ColoredBox(color: Color(0xFF2B2B2B))
                      : BlobBackground(seed: post.id, color: color),
                )
              else if (post.isVideo)
                const ColoredBox(color: Color(0xFF2B2B2B))
              else
                BlobBackground(seed: post.id, color: color),
              // 점진 블러 — 같은 사진의 블러 사본을 세로 그라데이션 마스크로
              // 페이드인(아래로 갈수록 진해짐, 경계선 없음).
              // ClipRect — 마스크가 완전 투명한 상단(0~42%)까지 블러를 래스터하지
              // 않도록, 실제 보이는 하단 구간만 잘라 그린다(블러 비용 ~40% 절감).
              if (displayUrl != null)
                Positioned.fill(
                  child: ClipRect(
                    clipper: const _BottomFractionClipper(0.40),
                    child: ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0x00FFFFFF),
                          Color(0xFFFFFFFF),
                        ],
                        stops: [0.0, 0.42, 0.85],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 22,
                          sigmaY: 22,
                          tileMode: ui.TileMode.clamp,
                        ),
                        child: Image.network(
                          displayUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 400, // 블러 사본 — 저해상 디코딩으로 충분
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              // 사진 없는 글: 본문을 히어로로 배치(하단 정보와 중복 없음) —
              // 하단 정보 구간을 제외한 영역의 정중앙에 정렬.
              if (!hasPhoto)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 170),
                    child: Center(
                      child: Text(
                        post.content,
                        textAlign: TextAlign.center,
                        maxLines: 9,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
              // 가독용 스크림.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 210,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x73000000)],
                    ),
                  ),
                ),
              ),
              // 정보 — 블러 구간 위.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _CategoryTag(category: post.category, color: color),
                          if (post.location != null &&
                              post.location!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: _DongTag(
                                label: post.location!,
                                moved: post.authorMoved,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            post.isEdited
                                ? '${timeAgo(post.createdAt)} · 수정됨'
                                : timeAgo(post.createdAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xCCFFFFFF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      // 본문 미리보기 — 사진 없는 글은 상단 히어로로 옮겨 중복 표시 안 함.
                      if (hasPhoto) ...[
                        const SizedBox(height: 4),
                        Text(
                          post.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xE0FFFFFF),
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (post.scheduledAt != null) ...[
                        const SizedBox(height: 10),
                        _MetaPill(
                          icon: Icons.event_outlined,
                          label:
                              '${post.scheduledAt!.month}/${post.scheduledAt!.day} ${post.scheduledAt!.hour}시',
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // 닉네임 탭 → 작성자 프로필(안쪽 제스처가 카드 탭보다 우선).
                          // 오프스크린 원점 — 아래에서 떠오르고, 당기거나 뒤로가기
                          // 하면 아래로 내려가며 닫힌다(모달 문법).
                          GestureDetector(
                            onTap: post.userId.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    CollapseRoute(
                                      builder: (_) => UserProfileScreen(
                                        userId: post.userId,
                                        previewNickname: post.authorNickname,
                                        originRect: riseOriginRect(context),
                                        cardRadius: 24,
                                        // 작성 모드가 얼굴을 결정(0025 연결 차단)
                                        forcePersonalFace:
                                            post.authoredAs != 'business',
                                      ),
                                    ),
                                  ),
                            child: Text(
                              post.authorNickname,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xE6FFFFFF),
                              ),
                            ),
                          ),
                          const Spacer(),
                          HeartButton(
                            active: post.hearted,
                            count: post.heartCount,
                            onTap: onHeart,
                          ),
                          const SizedBox(width: 14),
                          _Stat(
                            icon: Icons.chat_bubble_outline,
                            value: post.commentCount,
                            color: const Color(0xCCFFFFFF),
                          ),
                          const SizedBox(width: 14),
                          _Stat(
                            icon: Icons.visibility_outlined,
                            value: post.viewCount,
                            color: const Color(0xCCFFFFFF),
                          ),
                        ],
                      ),
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

class _CategoryTag extends StatelessWidget {
  final String category;
  final Color color;
  const _CategoryTag({required this.category, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // 사진/스크림 위에서도 읽히도록 밝은 필름 배경.
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        categoryLabel(category),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 작성자 활동지역(동 단위) 태그 — 카테고리 옆.
/// [moved] = 작성자가 현재 다른 지역에 있음(작성 당시 동과 다름) → 경고색 + 아이콘.
class _DongTag extends StatelessWidget {
  final String label;
  final bool moved;
  const _DongTag({required this.label, this.moved = false});

  // 흰 필름 알약 위에서도 읽히는 진한 앰버(warning 의 저명도 변형).
  static const _warnDark = Color(0xFF8F6E2F);

  @override
  Widget build(BuildContext context) {
    final color = moved ? _warnDark : const Color(0xE6FFFFFF);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          moved ? Icons.info_outline : Icons.place_outlined,
          size: 13,
          color: moved ? _warnDark : const Color(0xCCFFFFFF),
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            moved ? '$label·이동' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
    if (!moved) return row;
    // 이동 경고는 사진/스크림 위에서 노란 글자만으로는 안 읽혀 —
    // 카테고리 태그와 같은 흰 필름 알약으로 받쳐준다.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
      ),
      child: row,
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 위쪽 [topFraction] 을 잘라내고 아래만 남기는 클리퍼 — 마스크로 어차피 안 보이는
/// 상단 구간의 블러 래스터를 건너뛰기 위한 것.
class _BottomFractionClipper extends CustomClipper<Rect> {
  final double topFraction;
  const _BottomFractionClipper(this.topFraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, size.height * topFraction, size.width, size.height);

  @override
  bool shouldReclip(_BottomFractionClipper oldClipper) =>
      oldClipper.topFraction != topFraction;
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  const _Stat({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
