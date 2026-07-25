import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/community.dart';
import '../motion/motion.dart';
import '../theme/app_palette.dart';
import 'media_widgets.dart';
import 'post_card.dart';

/// 영상 게시글 상세의 쇼츠형 히어로 — 커뮤니티 카드 디자인을 유지한 채 영상만
/// 전체화면으로 확장한 화면. 부모(뷰포트 높이 박스)를 가득 채운다.
///
/// - 세로·정방형 영상은 cover 로 풀스크린, 가로 영상은 검정 배경 위 contain.
/// - 하단 오버레이는 피드 카드와 동일 위젯([PostCardInfoOverlay])을 공유하고,
///   블러는 그 뒤에만 깐다: 피드 카드와 같은 방식으로 같은 영상을 한 겹 더
///   그려(σ22) 세로 그라데이션 마스크로 페이드인 — 마스크가 연속이라 경계·
///   계단이 없다. 카드와 같은 그라데이션 스크림을 겹친다.
/// - 컨트롤은 쇼츠 문법: 영상 탭 = 재생/일시정지(일시정지 시에만 중앙 ▶),
///   화면 최하단의 얇은 진행바 하나(드래그 스크럽). 소리 UI 없음.
/// - 축소(카드 복귀) 전환이 시작되면 영상을 3:4 상단 박스로, 오버레이를 카드
///   위치로 되돌려(150ms) [CollapsibleView] 의 축소 모프가 피드 카드와 겹친다.
///   진행바는 페이드아웃.
class PostVideoHero extends StatefulWidget {
  final Post post;
  final VideoPlayerController controller;

  /// 영상 초기화/재생 실패 — 어두운 타일 + 안내로 폴백.
  final bool error;
  final VoidCallback? onHeart;

  /// 오버레이의 댓글 아이콘 탭 → 댓글 바텀시트.
  final VoidCallback? onComments;

  const PostVideoHero({
    super.key,
    required this.post,
    required this.controller,
    this.error = false,
    this.onHeart,
    this.onComments,
  });

  @override
  State<PostVideoHero> createState() => _PostVideoHeroState();
}

class _PostVideoHeroState extends State<PostVideoHero> {
  Animation<double>? _progress;

  /// 축소/확장 전환 중(진행도 < 1) — 카드와 동일한 3:4·접힘 배치로 강제해
  /// 축소 모프가 피드 카드와 겹치게 한다(_BlobHero 와 같은 문법).
  bool _mirror = false;
  bool _initialized = false;

  /// 본문 펼침 상태 — 축소 전환 중에는 강제로 접히고, 드래그가 취소되어
  /// 풀스크린으로 복귀하면 다시 펼쳐진다.
  bool _expanded = false;

  void _onTick() {
    final want = (_progress?.value ?? 1) < 1.0;
    if (want != _mirror && mounted) setState(() => _mirror = want);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = CollapseProgress.of(context);
    if (!identical(p, _progress)) {
      _progress?.removeListener(_onTick);
      _progress = p;
      _progress?.addListener(_onTick);
    }
    if (!_initialized) {
      _initialized = true;
      // 전환 없이 열린 화면(비확장 진입)은 처음부터 풀스크린 배치.
      _mirror = (p?.value ?? 1) < 1.0;
    }
  }

  @override
  void dispose() {
    _progress?.removeListener(_onTick);
    super.dispose();
  }

  /// 카드 복귀는 전환이 끝나기 전에 빠르게, 풀스크린 안착은 여유 있게
  /// (_BlobHero 와 동일한 템포).
  Duration get _anchorDuration => Duration(milliseconds: _mirror ? 150 : 380);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, v, _) => LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // 축소 전환 중엔 피드 카드와 같은 3:4 상단 박스로.
          final cardH = w / kPostImageAspectRatio;
          final videoBoxH = _mirror ? cardH : h;
          // 세로·정방형은 cover(풀스크린), 가로 영상은 검정 위 contain.
          // 카드 미러 중엔 카드(포스터 cover)와 겹치도록 cover 로.
          final landscape = v.isInitialized && v.aspectRatio > 1;
          final fit = landscape && !_mirror ? BoxFit.contain : BoxFit.cover;
          final expanded = _expanded && !_mirror;
          final safeBottom = MediaQuery.paddingOf(context).bottom;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              // 영상 — 풀스크린, 축소 전환 중엔 3:4 상단 박스.
              AnimatedPositioned(
                duration: _anchorDuration,
                curve: Curves.easeOutCubic,
                top: 0,
                left: 0,
                right: 0,
                height: videoBoxH,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black), // letterbox 여백
                      if (widget.error)
                        const ColoredBox(
                          color: kVideoFallbackBg,
                          child: Center(child: VideoErrorLabel()),
                        )
                      else ...[
                        if (v.isInitialized)
                          FittedBox(
                            fit: fit,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: v.size.width,
                              height: v.size.height,
                              child: VideoPlayer(widget.controller),
                            ),
                          ),
                        // 포스터 — 초기화 전 cover 로 채우고, 준비되면 페이드아웃.
                        IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: v.isInitialized ? 0 : 1,
                            duration: const Duration(milliseconds: 250),
                            child: widget.post.imageThumbUrl != null
                                ? Image.network(
                                    widget.post.imageThumbUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const ColoredBox(
                                      color: kVideoFallbackBg,
                                    ),
                                  )
                                : const ColoredBox(color: kVideoFallbackBg),
                          ),
                        ),
                        if (!v.isInitialized)
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                          ),
                        // 탭 = 재생/일시정지. 일시정지 시에만 중앙 ▶(쇼츠 문법).
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => toggleVideoPlayback(widget.controller),
                            child: AnimatedOpacity(
                              opacity: v.isInitialized && !v.isPlaying ? 1 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: const Center(
                                child: IgnorePointer(
                                  child: VideoPlayBadge(size: 56),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // 하단 오버레이 패널 — 카드 미러 정보 + 그 뒤에만 점진 블러·스크림.
              // 풀스크린에선 화면 하단, 축소 전환 중엔 카드(3:4) 하단으로 이동.
              AnimatedPositioned(
                duration: _anchorDuration,
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: _mirror ? h - cardH : 0,
                child: _OverlayPanel(
                  // 블러 사본 — 카드와 동일한 방식(같은 소스를 한 겹 더 그려
                  // σ22 블러 + 마스크). 영상 박스 하단 == 패널 하단이므로
                  // 바닥 정렬 OverflowBox 로 뒤 픽셀과 정확히 겹친다.
                  blurSourceSize: Size(w, videoBoxH),
                  blurSource: widget.error
                      ? const ColoredBox(color: kVideoFallbackBg)
                      : v.isInitialized
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Colors.black),
                            FittedBox(
                              fit: fit,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: v.size.width,
                                height: v.size.height,
                                child: VideoPlayer(widget.controller),
                              ),
                            ),
                          ],
                        )
                      : widget.post.imageThumbUrl != null
                      ? Image.network(
                          widget.post.imageThumbUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: kVideoFallbackBg),
                        )
                      : const ColoredBox(color: kVideoFallbackBg),
                  // 풀스크린에선 진행바·홈 인디케이터 위로 띄우고,
                  // 카드 미러에선 카드와 동일하게 바닥에 붙인다.
                  // 진행바(안전영역 위 2px, 터치 높이 18px)와 겹치지 않는 여백.
                  bottomClearance: _mirror ? 0 : safeBottom + 24,
                  clearanceDuration: _anchorDuration,
                  child: PostCardInfoOverlay(
                    post: widget.post,
                    onHeart: widget.onHeart,
                    onComments: widget.onComments,
                    expanded: expanded,
                    expandedMaxHeight: h * 0.5,
                    onToggleExpand: _mirror
                        ? null
                        : () => setState(() => _expanded = !_expanded),
                  ),
                ),
              ),
              // 재생 진행바 — 하단 경계선(드래그 스크럽 가능). 홈 인디케이터와
              // 겹치지 않게 안전영역 위로 살짝 올려 둔다.
              // 축소 전환이 시작되면 페이드아웃(카드에 없는 요소).
              if (!widget.error && v.isInitialized)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: safeBottom + 2,
                  child: AnimatedOpacity(
                    opacity: _mirror ? 0 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: SizedBox(
                      height: 18,
                      child: VideoProgressIndicator(
                        widget.controller,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: context.colors.primary,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                        // 시각적 트랙은 하단 ~3.5px, 위쪽은 스크럽 터치 여유.
                        padding: const EdgeInsets.only(top: 14.5),
                      ),
                    ),
                  ),
                ),
              // 상태바 스크림 — 어두운 영상에서도 시간·배터리가 읽히게.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.paddingOf(context).top + 24,
                child: const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white70, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 오버레이 뒤에만 깔리는 점진 블러 패널 — 높이는 콘텐츠(카드 미러 오버레이)가
/// 결정한다. 블러는 피드 카드와 **같은 방식**: 같은 소스([blurSource])를 한 겹
/// 더 그려 σ22 로 블러하고 세로 그라데이션 마스크(dstIn)로 페이드인 — 마스크가
/// 연속이라 밴드·계단이 원천적으로 없고 블러 패스도 1번이다. 카드와 같은
/// 스크림을 겹쳐 가독을 보정한다.
class _OverlayPanel extends StatelessWidget {
  final Widget child;

  /// 블러 사본의 원본 — 뒤에 깔린 영상 박스와 동일한 서브트리.
  /// [blurSourceSize] = 영상 박스 크기. 영상 박스 하단과 패널 하단이 일치하므로
  /// 바닥 정렬 OverflowBox 로 그리면 패널 뒤 픽셀과 정확히 겹친다.
  final Widget blurSource;
  final Size blurSourceSize;

  /// 콘텐츠 아래 여백(진행바·홈 인디케이터 위) — 카드 미러에선 0.
  final double bottomClearance;
  final Duration clearanceDuration;

  const _OverlayPanel({
    required this.child,
    required this.blurSource,
    required this.blurSourceSize,
    required this.bottomClearance,
    required this.clearanceDuration,
  });

  /// 마스크 페이드 구간 — 패널 상단에서 이만큼에 걸쳐 투명 → 불투명.
  static const double _fadeHeight = 96;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 점진 블러 — 카드의 블러 사본 문법(ClipRect → ShaderMask → ImageFiltered).
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
                  stops: [0.0, (_fadeHeight / rect.height).clamp(0.0, 1.0)],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ImageFiltered(
                  // 카드(σ22)보다 절반 수준 — 전체화면에선 영상 질감이 더 비치게.
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 11,
                    sigmaY: 11,
                    tileMode: ui.TileMode.clamp,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: OverflowBox(
                      minWidth: blurSourceSize.width,
                      maxWidth: blurSourceSize.width,
                      minHeight: blurSourceSize.height,
                      maxHeight: blurSourceSize.height,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox.fromSize(
                        size: blurSourceSize,
                        child: blurSource,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 가독용 스크림 — 카드와 같은 그라데이션(위 투명 → 아래 45% 검정).
        const Positioned.fill(
          child: IgnorePointer(
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
        ),
        // 콘텐츠 — 패널 크기의 기준(위 페이드 구간 + 오버레이 + 하단 여백).
        Padding(
          padding: const EdgeInsets.only(top: _fadeHeight),
          child: AnimatedPadding(
            duration: clearanceDuration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: bottomClearance),
            child: child,
          ),
        ),
      ],
    );
  }
}
