import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/community.dart';
import '../motion/motion.dart';
import '../theme/app_palette.dart';
import 'blob_background.dart';
import 'media_widgets.dart';
import 'post_card.dart';
import 'role_badge.dart' show categoryColor;

/// 게시글 상세의 미디어 히어로 — 커뮤니티 카드 디자인을 유지한 채 미디어만
/// 전체화면으로 확장한 화면(쇼츠 문법). 부모(뷰포트 높이 박스)를 가득 채우며
/// 영상·사진·블롭(사진 없는 글) 전 카테고리가 같은 구조를 쓴다.
///
/// - 영상: 세로·정방형 cover 풀스크린, 가로는 검정 위 contain. 탭 = 재생/일시
///   정지(일시정지 시에만 중앙 ▶), 화면 최하단 얇은 진행바(드래그 스크럽).
/// - 사진: 카드 대표사진이 그대로 화면 전체(cover).
/// - 블롭: 카드의 블롭 배경 + 본문 센터 배치를 풀스크린으로 승격(본문 탭으로
///   펼침/접힘 — 블러 없이 카드처럼 스크림만).
/// - 하단 오버레이는 피드 카드와 동일 위젯([PostCardInfoOverlay])을 공유하고,
///   블러는 그 뒤에만: 피드 카드와 같은 방식으로 같은 미디어를 한 겹 더 그려
///   σ8 블러 + 세로 그라데이션 마스크 — 마스크가 연속이라 경계·계단이 없다.
///   본문 탭으로 펼치면 패널(블러 포함)이 위로 자라며 칩·제목이 밀려 올라간다.
/// - 축소(카드 복귀) 전환이 시작되면 미디어를 3:4 **세로 중앙** 박스로,
///   오버레이를 그 하단으로 되돌려(150ms) [CollapsibleView] 의 중심 기준
///   사방 축소 모프(contentAlignment: center)와 피드 카드가 겹친다.
///   카드에 없는 요소(진행바·지원 버튼)는 페이드아웃.
class PostMediaHero extends StatefulWidget {
  final Post post;

  /// 영상 글의 재생 컨트롤러(화면이 소유). null 이면 사진/블롭 글.
  final VideoPlayerController? controller;

  /// 영상 초기화/재생 실패 — 어두운 타일 + 안내로 폴백.
  final bool videoError;
  final VoidCallback? onHeart;

  /// 오버레이의 댓글 아이콘 탭 → 댓글 바텀시트.
  final VoidCallback? onComments;

  /// 상세 전용 오버레이 부가 섹션(지원하기 버튼 등) — 본문/약속 필과 하단
  /// 스탯 행 사이. 카드에 없는 요소라 축소 전환 중엔 페이드아웃한다.
  final Widget? overlayExtra;

  /// 닉네임 탭(프로필 무한 왕복 방지 pop 처리 포함) — 상세 화면이 결정.
  final VoidCallback? onAuthorTap;

  /// 오버레이 몰입 숨김 상태 변경 통지(사진 글 탭 토글) — 화면이 앱바
  /// 오버레이 아이콘을 함께 숨기는 데 쓴다.
  final ValueChanged<bool>? onOverlayHiddenChanged;

  const PostMediaHero({
    super.key,
    required this.post,
    this.controller,
    this.videoError = false,
    this.onHeart,
    this.onComments,
    this.overlayExtra,
    this.onAuthorTap,
    this.onOverlayHiddenChanged,
  });

  @override
  State<PostMediaHero> createState() => _PostMediaHeroState();
}

class _PostMediaHeroState extends State<PostMediaHero> {
  Animation<double>? _progress;

  /// 축소/확장 전환 중(진행도 < 1) — 카드와 동일한 3:4·접힘 배치로 강제해
  /// 축소 모프가 피드 카드와 겹치게 한다(기존 블롭 히어로와 같은 문법).
  bool _mirror = false;
  bool _initialized = false;

  /// 본문 펼침 상태(오버레이 미리보기 또는 블롭 센터 본문) — 진입하면 자동으로
  /// 펼쳐진다(확장 전환이 안착한 뒤 스프링으로 열림 — expanded 는
  /// `_expanded && !_mirror` 라 카드 미러가 풀리는 순간 AnimatedSize 가 받는다).
  /// 탭으로 접기/다시 펼치기 토글, 축소 전환 중에는 강제로 접히고 드래그가
  /// 취소되어 풀스크린으로 복귀하면 다시 펼쳐진다.
  bool _expanded = true;

  /// 오버레이(블러 패널) 몰입 숨김 — 사진 글에서 화면 탭으로 토글(영상은 탭이
  /// 재생/일시정지라 제외). 축소 전환이 시작되면 자동 복귀(카드엔 오버레이가
  /// 있으므로 페이드 인하며 카드 미러로 수축).
  bool _overlayHidden = false;

  void _onTick() {
    final want = (_progress?.value ?? 1) < 1.0;
    if (want != _mirror && mounted) {
      setState(() {
        _mirror = want;
        // 축소 전환 시작 → 숨겨둔 오버레이 자동 복귀(드래그 취소로 풀스크린에
        // 돌아와도 보이는 상태 유지).
        if (want && _overlayHidden) {
          _overlayHidden = false;
          widget.onOverlayHiddenChanged?.call(false);
        }
      });
    }
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

  /// 카드 복귀는 전환이 끝나기 전에 빠르게, 풀스크린 안착은 여유 있게.
  Duration get _anchorDuration => Duration(milliseconds: _mirror ? 150 : 380);

  bool get _isBlob => widget.controller == null && widget.post.imageUrl == null;

  /// 사진 글 — 탭 토글(오버레이 숨김) 대상.
  bool get _isPhoto =>
      widget.controller == null && widget.post.imageUrl != null;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  void _toggleOverlayHidden() {
    setState(() => _overlayHidden = !_overlayHidden);
    widget.onOverlayHiddenChanged?.call(_overlayHidden);
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.controller;
    if (video != null) {
      // 영상 — 재생 상태(초기화·재생/일시정지·진행)에 반응.
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: video,
        builder: (context, v, _) => _buildHero(context, v),
      );
    }
    return _buildHero(context, null);
  }

  Widget _buildHero(BuildContext context, VideoPlayerValue? v) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 축소 전환 중엔 피드 카드와 같은 3:4 박스를 **화면 세로 중앙**에 —
        // CollapsibleView 의 중심 기준(사방) 확장(contentAlignment: center)과
        // 짝을 이뤄 윈도 중심과 카드 미러가 항상 겹친다.
        final cardH = w / kPostImageAspectRatio;
        final boxH = _mirror ? cardH : h;
        final mirrorInset = (h - cardH) / 2;
        // 영상: 세로·정방형은 cover(풀스크린), 가로는 검정 위 contain.
        // 카드 미러 중엔 카드(포스터 cover)와 겹치도록 cover 로. 사진은 늘 cover.
        final landscape = v != null && v.isInitialized && v.aspectRatio > 1;
        final fit = landscape && !_mirror ? BoxFit.contain : BoxFit.cover;
        final expanded = _expanded && !_mirror;
        // 몰입 숨김 — 축소 전환 중엔 항상 표시(카드 미러엔 오버레이가 있다).
        final overlayHidden = _overlayHidden && !_mirror;
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final isBlob = _isBlob;
        return Stack(
          fit: StackFit.expand,
          children: [
            // 배경은 투명 — 풀스크린에선 미디어 박스가 화면을 다 덮고, 축소
            // 전환 중엔 카드(3:4) 밖이 비어 뒤 피드가 비친다
            // (CollapseRoute opaque:false).
            // 미디어 — 풀스크린, 축소 전환 중엔 3:4 세로 중앙 박스.
            AnimatedPositioned(
              duration: _anchorDuration,
              curve: Curves.easeOutCubic,
              top: _mirror ? mirrorInset : 0,
              left: 0,
              right: 0,
              height: boxH,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _mediaSurface(context, v, fit),
                    // 사진 글 — 화면 탭 = 오버레이(블러+정보) 몰입 숨김/복귀.
                    // 영상은 탭이 재생/일시정지라 제외(충돌 방지).
                    if (_isPhoto)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _mirror ? null : _toggleOverlayHidden,
                        ),
                      ),
                    // 블롭 글 — 카드처럼 본문이 히어로의 중심(탭으로 펼침/접힘).
                    if (isBlob)
                      Positioned.fill(
                        child: BlobHeroContent(
                          content: widget.post.content,
                          mirror: _mirror,
                          expanded: expanded,
                          expandedMaxHeight: h * 0.55,
                          anchorDuration: _anchorDuration,
                          onToggle: _mirror ? null : _toggleExpanded,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 하단 오버레이 패널 — 카드 미러 정보 + 그 뒤에만 점진 블러·스크림.
            // 풀스크린에선 화면 하단, 축소 전환 중엔 카드(세로 중앙 3:4) 하단으로.
            AnimatedPositioned(
              duration: _anchorDuration,
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: _mirror ? mirrorInset : 0,
              // 몰입 숨김 — 부드럽게 사라지고, 축소 전환이 시작되면 페이드 인
              // 으로 복귀하면서 카드 미러로 수축한다.
              child: IgnorePointer(
                ignoring: overlayHidden,
                child: AnimatedOpacity(
                  opacity: overlayHidden ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: MediaOverlayPanel(
                    // 블러 사본 — 카드와 동일한 방식(같은 소스를 한 겹 더 그려
                    // σ8 블러 + 마스크). 미디어 박스 하단 == 패널 하단이므로
                    // 바닥 정렬 OverflowBox 로 뒤 픽셀과 정확히 겹친다.
                    // 블롭 글은 카드처럼 블러 없이 스크림만.
                    blurSource: _blurSource(v),
                    blurSourceSize: Size(w, boxH),
                    // 풀스크린에선 진행바·홈 인디케이터 위로 띄우고,
                    // 카드 미러에선 카드와 동일하게 바닥에 붙인다.
                    bottomClearance: _mirror
                        ? 0
                        : safeBottom + (v != null ? 24 : 10),
                    clearanceDuration: _anchorDuration,
                    child: PostCardInfoOverlay(
                      post: widget.post,
                      onHeart: widget.onHeart,
                      onComments: widget.onComments,
                      // 블롭 글의 본문은 히어로 센터에 있어 미리보기 중복 표시 안 함
                      // (카드와 동일).
                      showContent: !isBlob,
                      expanded: expanded,
                      expandedMaxHeight: h * 0.5,
                      onToggleExpand: isBlob || _mirror
                          ? null
                          : _toggleExpanded,
                      extra: widget.overlayExtra,
                      extraVisible: !_mirror,
                      detailMeta: true,
                      onAuthorTap: widget.onAuthorTap,
                    ),
                  ),
                ),
              ),
            ),
            // 재생 진행바(영상 글) — 하단 경계선(드래그 스크럽 가능). 홈
            // 인디케이터와 겹치지 않게 안전영역 위로 살짝 올려 둔다.
            // 축소 전환이 시작되면 페이드아웃(카드에 없는 요소).
            if (v != null && !widget.videoError && v.isInitialized)
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
                      widget.controller!,
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
            // 상태바 스크림 — 어두운 미디어에서도 시간·배터리가 읽히게.
            // 블롭 배경은 밝아 불필요(카드와 동일). 확장·축소 전환 중에는
            // 카드에 없는 요소라 회색 띠로 보이므로 페이드 아웃.
            if (!isBlob)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.paddingOf(context).top + 24,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _mirror ? 0 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: const DecoratedBox(
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
              ),
          ],
        );
      },
    );
  }

  /// 미디어 박스 본체 — 영상(재생/포스터/에러), 사진(cover), 블롭 배경.
  /// 영상 표면 — 네이티브는 `FittedBox`(넘치는 만큼 잘라 채움), 웹은 `AspectRatio`.
  ///
  /// ⚠️ 웹에서 `FittedBox(clipBehavior: hardEdge)` 를 쓰면 안 된다.
  /// `video_player_web` 의 영상은 `HtmlElementView`(DOM `<video>`)이고 플랫폼 뷰는
  /// 캔버스 밖에서 합성되므로 **클립이 먹지 않는다**. 원본 크기(예: 1080×1920)를
  /// cover 로 확대하면 넘치는 부분이 잘리지 않고 그대로 박스 밖으로 흘러넘쳐
  /// 위아래 UI 를 덮는다(실측: 박스 밖 위로 -50px, 아래로 +50px).
  ///
  /// 그래서 웹은 **박스를 영상 비율에 맞춰** 애초에 넘칠 것이 없게 한다. cover 가
  /// contain 이 되어 여백(레터박스)이 생기지만, 뒤에 검정 배경이 이미 깔려 있어
  /// 자연스럽고 잘림보다 낫다. 네이티브는 기존 동작 그대로.
  Widget _videoSurface(VideoPlayerValue v, BoxFit fit) {
    final player = VideoPlayer(widget.controller!);
    if (kIsWeb) {
      return Center(
        child: AspectRatio(aspectRatio: v.aspectRatio, child: player),
      );
    }
    return FittedBox(
      fit: fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: v.size.width,
        height: v.size.height,
        child: player,
      ),
    );
  }

  Widget _mediaSurface(BuildContext context, VideoPlayerValue? v, BoxFit fit) {
    final post = widget.post;
    if (v != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black), // letterbox 여백
          if (widget.videoError)
            const ColoredBox(
              color: kVideoFallbackBg,
              child: Center(child: VideoErrorLabel()),
            )
          else ...[
            if (v.isInitialized) _videoSurface(v, fit),
            // 포스터 — 초기화 전 cover 로 채우고, 준비되면 페이드아웃.
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
            // 탭 = 재생/일시정지. 일시정지 시에만 중앙 ▶(쇼츠 문법).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => toggleVideoPlayback(widget.controller!),
                child: AnimatedOpacity(
                  opacity: v.isInitialized && !v.isPlaying ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Center(
                    child: IgnorePointer(child: VideoPlayBadge(size: 56)),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (post.imageUrl != null) {
      // 사진 — 카드와 같은 디코딩 폭이라 피드에서 캐시된 이미지를 재사용한다.
      return Image.network(
        post.imageUrl!,
        fit: BoxFit.cover,
        cacheWidth: 1200,
        errorBuilder: (_, _, _) => BlobBackground(
          seed: post.id,
          color: categoryColor(context, post.category),
        ),
      );
    }
    // 블롭 — 카드와 동일한 배경(본문은 별도 레이어).
    return BlobBackground(
      seed: post.id,
      color: categoryColor(context, post.category),
    );
  }

  /// 패널 블러의 원본 사본 — 뒤에 깔린 미디어와 동일한 서브트리.
  /// 블롭 글은 null(카드처럼 블러 없이 스크림만).
  ///
  /// ⚠️ 웹에서는 영상 사본을 쓰지 않는다. `video_player_web` 은 영상을
  /// `HtmlElementView`(DOM `<video>`)로 그리는데, 플랫폼 뷰는 캔버스 밖에서
  /// 합성되므로 `ImageFiltered`·`ShaderMask` 가 먹지 않고 `ClipRect` 도 따라오지
  /// 않는다. 그래서 블러 사본으로 만든 두 번째 `<video>` 가 진짜 영상 위로
  /// 삐져나와 **영상이 잘려 보였다**. 웹에서는 포스터(정지 프레임)를 블러한다 —
  /// σ8 로 뭉개지는 하단 패널이라 정지 프레임과 구분이 거의 안 된다.
  Widget? _blurSource(VideoPlayerValue? v) {
    final post = widget.post;
    if (v != null) {
      if (widget.videoError) return const ColoredBox(color: kVideoFallbackBg);
      if (v.isInitialized && !kIsWeb) {
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            FittedBox(
              fit: v.aspectRatio > 1 && !_mirror
                  ? BoxFit.contain
                  : BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: v.size.width,
                height: v.size.height,
                child: VideoPlayer(widget.controller!),
              ),
            ),
          ],
        );
      }
      return post.imageThumbUrl != null
          ? Image.network(
              post.imageThumbUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: kVideoFallbackBg),
            )
          : const ColoredBox(color: kVideoFallbackBg);
    }
    if (post.imageUrl != null) {
      // 사진 — 카드의 블러 사본과 동일(저해상 디코딩으로 충분).
      return Image.network(
        post.imageUrl!,
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return null; // 블롭
  }
}

/// 블롭 글의 센터 본문(게시글·후기 상세 공용) — 카드와 동일한 배치(축소 전환 중엔 카드의 하단 정보
/// 여백 170 기준)로 전환을 잇고, 풀스크린에선 오버레이 패널 위 공간의 중심.
/// 본문이 9줄을 넘치면 말줄임(…)으로 접히고 탭으로 펼침/접힘(내부 스크롤 제한).
class BlobHeroContent extends StatelessWidget {
  final String content;
  final bool mirror;
  final bool expanded;
  final double expandedMaxHeight;
  final Duration anchorDuration;
  final VoidCallback? onToggle;

  const BlobHeroContent({
    super.key,
    required this.content,
    required this.mirror,
    required this.expanded,
    required this.expandedMaxHeight,
    required this.anchorDuration,
    required this.onToggle,
  });

  /// 카드의 블롭 본문 줄수(피드 카드와 동일).
  static const int _previewLines = 9;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: context.colors.textPrimary,
      height: 1.6,
    );
    return AnimatedPadding(
      duration: anchorDuration,
      curve: Curves.easeOutCubic,
      // 카드 미러: 카드와 동일(하단 정보 여백 170). 풀스크린: 상태바 아래 ~
      // 오버레이 패널 위 공간의 중심.
      padding: mirror
          ? const EdgeInsets.fromLTRB(22, 24, 22, 170)
          : EdgeInsets.fromLTRB(
              22,
              MediaQuery.paddingOf(context).top + 24,
              22,
              280,
            ),
      child: Center(
        child: AnimatedSize(
          duration: MotionDurations.base,
          curve: SpringCurve.standard,
          alignment: Alignment.center,
          child: LayoutBuilder(
            builder: (context, c) {
              final painter = TextPainter(
                text: TextSpan(text: content, style: style),
                maxLines: _previewLines,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: c.maxWidth);
              final overflows = painter.didExceedMaxLines;
              painter.dispose();
              final text = Text(
                content,
                textAlign: TextAlign.center,
                maxLines: expanded ? null : _previewLines,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: style,
              );
              final body = expanded
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: expandedMaxHeight),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: text,
                      ),
                    )
                  : text;
              // 본문 탭 = 펼침/접힘(넘칠 때만 — 쇼츠 문법, 버튼 없음).
              if (onToggle == null || (!overflows && !expanded)) return body;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: body,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 오버레이 뒤에만 깔리는 점진 블러 패널 — 게시글·시설 후기 상세가 공유한다.
/// 높이는 콘텐츠(카드 미러 오버레이)가
/// 결정한다. 블러는 피드 카드와 **같은 방식**: 같은 소스([blurSource])를 한 겹
/// 더 그려 σ8 로 블러하고 세로 그라데이션 마스크(dstIn)로 페이드인 — 마스크가
/// 연속이라 밴드·계단이 원천적으로 없고 블러 패스도 1번이다. 카드와 같은
/// 스크림을 겹쳐 가독을 보정한다. [blurSource] 가 null(블롭 글)이면 스크림만.
class MediaOverlayPanel extends StatelessWidget {
  final Widget child;

  /// 블러 사본의 원본 — 뒤에 깔린 미디어 박스와 동일한 서브트리.
  /// [blurSourceSize] = 미디어 박스 크기. 미디어 박스 하단과 패널 하단이
  /// 일치하므로 바닥 정렬 OverflowBox 로 그리면 패널 뒤 픽셀과 정확히 겹친다.
  final Widget? blurSource;
  final Size blurSourceSize;

  /// 콘텐츠 아래 여백(진행바·홈 인디케이터 위) — 카드 미러에선 0.
  final double bottomClearance;
  final Duration clearanceDuration;

  const MediaOverlayPanel({
    super.key,
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
        if (blurSource != null)
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
                    // 카드(σ22)보다 낮게 — 전체화면에선 미디어 질감이 더 비치게.
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 8,
                      sigmaY: 8,
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
