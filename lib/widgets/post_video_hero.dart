import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../models/community.dart';
import '../motion/motion.dart';
import 'media_widgets.dart';
import 'post_card.dart';

/// 영상 게시글 상세의 히어로 — 원본 화면 비율 영상 위에 피드 카드와 동일한
/// 점진 블러·스크림·정보 오버레이([PostCardInfoOverlay])를 미러링한다.
///
/// - 초기화 전에는 포스터를 카드와 같은 3:4 로 보여주다가, 컨트롤러가 준비되면
///   원본 비율로 부드럽게 전환한다(세로로 매우 긴 영상은 뷰포트 높이 75% 로
///   클램프하고 letterbox).
/// - 카드의 "이미지 블러 사본" 방식은 영상에 쓸 수 없으므로, 하단을 백드롭
///   블러 3단(아래로 갈수록 진해짐)으로 근사하고 카드와 같은 스크림을 얹는다.
/// - 오버레이의 본문은 더보기/접기로 펼칠 수 있고, 확장분은 히어로(영상)를
///   침범하지 않고 아래로 이어지는 어두운 패널로 자란다 — 닉네임·스탯 행과
///   아래 섹션들이 자연스럽게 밀려난다.
/// - 축소(카드 복귀) 전환이 시작되면 즉시 3:4·접힘 상태(카드 미러)로 되돌려
///   [CollapsibleView] 의 축소 모프가 피드 카드와 그대로 겹치게 한다.
class PostVideoHero extends StatefulWidget {
  final Post post;
  final VideoPlayerController controller;

  /// 영상 초기화/재생 실패 — 어두운 타일 + 안내로 폴백(3:4 유지).
  final bool error;
  final VoidCallback? onHeart;

  const PostVideoHero({
    super.key,
    required this.post,
    required this.controller,
    this.error = false,
    this.onHeart,
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

  /// 본문 펼침 상태. 축소 전환 중에는 강제로 접히고(_mirror), 드래그가
  /// 취소되어 풀스크린으로 복귀하면 다시 펼쳐진다.
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

  // 고스트(측정 전용)용 — 실제 오버레이와 같은 "버튼 노출" 구성을 만들기 위한 no-op.
  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, v, _) => LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // 히어로 비율 — 기본은 카드와 같은 3:4(포스터 대기·에러·축소 전환),
          // 초기화되면 원본 비율. 세로로 매우 긴 영상은 뷰포트 75% 로 클램프.
          double aspect = kPostImageAspectRatio;
          if (!_mirror &&
              !widget.error &&
              v.isInitialized &&
              v.aspectRatio > 0) {
            final viewportH = MediaQuery.sizeOf(context).height;
            final minAspect = w / (viewportH * 0.75);
            aspect = math.max(v.aspectRatio, minAspect);
          }
          final videoH = w / aspect;
          final expanded = _expanded && !_mirror;
          // 축소 전환 중엔 더보기 버튼까지 숨겨 카드와 완전히 같은 높이로.
          final toggle = _mirror
              ? null
              : () => setState(() => _expanded = !_expanded);
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: videoH, end: videoH),
            // 축소 복귀는 전환이 끝나기 전에 빠르게(_BlobHero 와 동일한 템포).
            duration: Duration(milliseconds: _mirror ? 150 : 420),
            curve: Curves.easeOutCubic,
            builder: (context, h, _) => _HeroBlock(
              videoHeight: h,
              background: _HeroBackground(
                post: widget.post,
                controller: widget.controller,
                videoHeight: h,
                error: widget.error,
                panelVisible: expanded,
              ),
              // 고스트 — 접힌 상태의 오버레이를 보이지 않게 측정만 해서,
              // 오버레이 상단(제목 위치)을 "카드와 겹치는 지점"에 고정한다.
              ghost: ExcludeSemantics(
                child: IgnorePointer(
                  child: PostCardInfoOverlay(
                    post: widget.post,
                    onToggleExpand: toggle == null ? null : _noop,
                  ),
                ),
              ),
              overlay: PostCardInfoOverlay(
                post: widget.post,
                onHeart: widget.onHeart,
                expanded: expanded,
                onToggleExpand: toggle,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 히어로 배경 — 영상 표면(원본 비율·letterbox), 포스터 폴백, 하단 점진 블러,
/// 카드와 동일한 스크림, 상태바 스크림, 본문 확장 패널.
class _HeroBackground extends StatelessWidget {
  final Post post;
  final VideoPlayerController controller;
  final double videoHeight;
  final bool error;

  /// 본문이 펼쳐져 히어로 아래로 패널이 이어지는 상태.
  final bool panelVisible;

  const _HeroBackground({
    required this.post,
    required this.controller,
    required this.videoHeight,
    required this.error,
    required this.panelVisible,
  });

  /// 확장 패널 색 — 스크림 끝을 이어받는 어두운 면(위에서 아래로 차오름).
  static const _panelColor = Color(0xFF222225);

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: videoHeight,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black), // letterbox 여백
                if (error)
                  const ColoredBox(
                    color: kVideoFallbackBg,
                    child: Center(child: VideoErrorLabel()),
                  )
                else ...[
                  if (v.isInitialized)
                    FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: v.size.width,
                        height: v.size.height,
                        child: VideoPlayer(controller),
                      ),
                    ),
                  // 포스터 — 초기화 전 카드와 동일한 커버 배치, 준비되면 페이드아웃.
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: v.isInitialized ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: post.imageThumbUrl != null
                          ? Image.network(
                              post.imageThumbUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: kVideoFallbackBg),
                            )
                          : const ColoredBox(color: kVideoFallbackBg),
                    ),
                  ),
                  if (!v.isInitialized)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    ),
                ],
                // 점진 블러 — 카드의 "블러 사본 + 세로 마스크"를 영상 위에서
                // 백드롭 블러 3단으로 근사(아래로 갈수록 시그마 누적 ≈ 22).
                if (!error) ...const [
                  _BlurBand(topFraction: 0.45, sigma: 8),
                  _BlurBand(topFraction: 0.60, sigma: 12),
                  _BlurBand(topFraction: 0.75, sigma: 16),
                ],
                // 가독용 스크림 — 카드와 동일.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 210,
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
                // 영상 탭 → 재생/일시정지(+ 일시정지 배지). 오버레이 정보가 위에
                // 쌓이므로 텍스트·버튼 밖의 영역만 받는다.
                if (!error)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => toggleVideoPlayback(controller),
                      child: AnimatedOpacity(
                        opacity: v.isInitialized && !v.isPlaying ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Center(
                          child: IgnorePointer(child: VideoPlayBadge(size: 56)),
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
            ),
          ),
        ),
        // 본문 확장 패널 — 영상 하단 스크림을 이어받아 히어로 아래로 자라는
        // 어두운 면. 접힌 상태에서는 투명(카드 미러 유지).
        Positioned(
          top: math.max(0, videoHeight - 72),
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: panelVisible ? 1 : 0,
              duration: MotionDurations.base,
              curve: Curves.easeOutCubic,
              child: const Column(
                children: [
                  SizedBox(
                    height: 72,
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00222225), _panelColor],
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: ColoredBox(color: _panelColor)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 하단 [1 - topFraction] 구간만 백드롭 블러하는 밴드 — 여러 장 겹쳐 점진 블러.
class _BlurBand extends StatelessWidget {
  final double topFraction;
  final double sigma;
  const _BlurBand({required this.topFraction, required this.sigma});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          clipper: BottomFractionClipper(topFraction),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

enum _HeroSlot { background, ghost, overlay }

/// 히어로 블록 레이아웃 — 핵심 불변식:
/// - 오버레이 상단은 `videoHeight - (접힌 오버레이 높이)` 에 고정된다.
///   → 접힌 상태의 블록 높이는 정확히 영상 높이(카드 미러),
///   → 본문이 펼쳐지면 확장분만큼 블록이 **아래로만** 자라 히어로를 침범하지
///     않고 이후 섹션들을 밀어낸다.
/// - "접힌 오버레이 높이"는 그리지 않는 고스트 자식을 같은 폭으로 측정해 얻는다
///   (본문 길이·태그 줄바꿈 등 어떤 구성에서도 정확).
class _HeroBlock
    extends SlottedMultiChildRenderObjectWidget<_HeroSlot, RenderBox> {
  const _HeroBlock({
    required this.videoHeight,
    required this.background,
    required this.ghost,
    required this.overlay,
  });

  final double videoHeight;
  final Widget background;
  final Widget ghost;
  final Widget overlay;

  @override
  Iterable<_HeroSlot> get slots => _HeroSlot.values;

  @override
  Widget? childForSlot(_HeroSlot slot) => switch (slot) {
    _HeroSlot.background => background,
    _HeroSlot.ghost => ghost,
    _HeroSlot.overlay => overlay,
  };

  @override
  _RenderHeroBlock createRenderObject(BuildContext context) =>
      _RenderHeroBlock(videoHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderHeroBlock renderObject) {
    renderObject.videoHeight = videoHeight;
  }
}

class _RenderHeroBlock extends RenderBox
    with SlottedContainerRenderObjectMixin<_HeroSlot, RenderBox> {
  _RenderHeroBlock(this._videoHeight);

  double _videoHeight;
  set videoHeight(double value) {
    if (value == _videoHeight) return;
    _videoHeight = value;
    markNeedsLayout();
  }

  RenderBox? get _background => childForSlot(_HeroSlot.background);
  RenderBox? get _ghost => childForSlot(_HeroSlot.ghost);
  RenderBox? get _overlay => childForSlot(_HeroSlot.overlay);

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final infoConstraints = BoxConstraints.tightFor(width: w);
    final ghost = _ghost;
    final overlay = _overlay;
    final background = _background;

    double ghostH = 0;
    double overlayH = 0;
    if (ghost != null) {
      ghost.layout(infoConstraints, parentUsesSize: true);
      ghostH = ghost.size.height;
    }
    if (overlay != null) {
      overlay.layout(infoConstraints, parentUsesSize: true);
      overlayH = overlay.size.height;
    }
    final top = math.max(0.0, _videoHeight - ghostH);
    final height = constraints.constrainHeight(
      math.max(_videoHeight, top + overlayH),
    );
    if (overlay != null) {
      (overlay.parentData! as BoxParentData).offset = Offset(0, top);
    }
    if (ghost != null) {
      (ghost.parentData! as BoxParentData).offset = Offset(0, top);
    }
    if (background != null) {
      background.layout(BoxConstraints.tight(Size(w, height)));
      (background.parentData! as BoxParentData).offset = Offset.zero;
    }
    size = Size(w, height);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // 고스트는 측정 전용 — 그리지 않는다.
    final background = _background;
    if (background != null) {
      context.paintChild(
        background,
        offset + (background.parentData! as BoxParentData).offset,
      );
    }
    final overlay = _overlay;
    if (overlay != null) {
      context.paintChild(
        overlay,
        offset + (overlay.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [_overlay, _background]) {
      if (child == null) continue;
      final childOffset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: childOffset,
        position: position,
        hitTest: (r, p) => child.hitTest(r, position: p),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final background = _background;
    if (background != null) visitor(background);
    final overlay = _overlay;
    if (overlay != null) visitor(overlay);
  }
}
