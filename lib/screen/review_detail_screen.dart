import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/facility_review.dart';
import '../motion/motion.dart';
import '../services/business_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/session.dart';
import '../theme/app_palette.dart';
import '../utils/labels.dart' show timeAgo;
import '../widgets/blob_background.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/media_widgets.dart';
import '../widgets/overlay_icon_button.dart';
import '../widgets/post_card.dart' show ExpandableOverlayText;
import '../widgets/post_media_hero.dart'
    show BlobHeroContent, MediaOverlayPanel;
import '../widgets/review_cards.dart';
import 'user_profile_screen.dart';

/// 시설 방문 후기 상세 — 게시글 상세와 동일한 쇼츠형 풀스크린 문법.
///
/// 미디어(사진 최대 5 + 영상 최대 2)가 화면 전체를 채우고 좌우 스와이프로
/// 넘긴다(PageView + 상단 1/N 인디케이터). 영상 페이지는 현재 페이지일 때만
/// 자동재생·루프하고, 탭 = 재생/일시정지, 최하단 얇은 진행바(게시글 문법).
/// 미디어 없는 후기는 후기 카드의 블롭 배경 + 본문 센터 배치를 풀스크린으로.
///
/// 하단 오버레이(카드 미러): 업체 혜택 배지(표시광고법 — 반드시 노출)·방문
/// 차수·날짜, 별점, 본문(탭 확장 — 블러 패널이 함께 위로 자람), 닉네임·댓글.
/// 블러는 게시글과 같은 σ8 사본+마스크. 댓글은 공용 바텀시트.
/// 아래로 당기면 카드로 축소(CollapsibleView — 기존 라우트 문법 유지).
class ReviewDetailScreen extends StatefulWidget {
  final ReviewCardData review;

  /// 탭한 카드의 화면상 사각형 — 있으면 그 자리에서 펼쳐지고/그 자리로 축소.
  final Rect? originRect;

  /// 축소 안착 시 크로스페이드할 실제 카드(피드의 PostCard 역할).
  final WidgetBuilder? cardBuilder;

  /// 알림 딥링크로 진입했는가 — 내가 이 시설의 업주인데 개인 모드면 진입 직후
  /// '업체 모드로 전환할까요?'를 물어 의도치 않은 개인 얼굴 댓글을 막는다.
  final bool fromDeepLink;

  const ReviewDetailScreen({
    super.key,
    required this.review,
    this.originRect,
    this.cardBuilder,
    this.fromDeepLink = false,
  });

  @override
  State<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

/// 미디어 페이지 — 사진 URL 또는 영상.
class _MediaPage {
  final String? photoUrl;
  final ReviewVideo? video;
  const _MediaPage.photo(this.photoUrl) : video = null;
  const _MediaPage.video(this.video) : photoUrl = null;
}

class _ReviewDetailScreenState extends State<ReviewDetailScreen> {
  final _scroll = ScrollController();

  // ── 미디어 페이징 ──
  late final List<_MediaPage> _pages = [
    for (final url in widget.review.photoUrls) _MediaPage.photo(url),
    for (final v in widget.review.videos) _MediaPage.video(v),
  ];
  final _pageCtrl = PageController();
  int _page = 0;

  /// 영상 페이지의 컨트롤러(페이지 인덱스 → 컨트롤러) — 화면이 소유.
  final Map<int, VideoPlayerController> _videoCtrls = {};
  final Set<int> _videoErrors = {};

  // ── 축소 전환(카드 미러) — 게시글 히어로와 같은 문법 ──
  Animation<double>? _progress;
  bool _mirror = false;
  bool _mirrorInit = false;

  /// 본문 펼침(오버레이 미리보기 또는 블롭 센터 본문).
  bool _expanded = false;

  // ── 댓글 — reviewId 가 있는 후기(시설 후기)에만 붙는다 ──
  final _commentCtrl = TextEditingController();
  List<FacilityReviewComment> _comments = [];
  bool _loadingComments = false;
  bool _sending = false;

  /// 댓글 시트 갱신 노티파이어 — 시트(별도 라우트)가 이 값으로 다시 그린다.
  final _commentsRev = ValueNotifier<int>(0);

  String? get _reviewId => widget.review.reviewId;
  bool get _loggedIn => SessionManager.instance.user != null;

  @override
  void initState() {
    super.initState();
    // 영상 페이지 컨트롤러 — 미리 만들고, 재생은 현재 페이지일 때만(루프).
    for (var i = 0; i < _pages.length; i++) {
      final v = _pages[i].video;
      if (v == null) continue;
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(v.url));
      _videoCtrls[i] = ctrl;
      ctrl.setLooping(true);
      ctrl
          .initialize()
          .then((_) {
            if (!mounted) return;
            setState(() {});
            if (_page == i) ctrl.play();
          })
          .catchError((Object e) {
            if (mounted) setState(() => _videoErrors.add(i));
          });
    }
    if (_reviewId != null) _loadComments();
    if (widget.fromDeepLink && _reviewId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeSuggestSwitch(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = CollapseProgress.of(context);
    if (!identical(p, _progress)) {
      _progress?.removeListener(_onCollapseTick);
      _progress = p;
      _progress?.addListener(_onCollapseTick);
    }
    if (!_mirrorInit) {
      _mirrorInit = true;
      // 전환 없이 열린 화면(비확장 진입)은 처음부터 풀스크린 배치.
      _mirror = (p?.value ?? 1) < 1.0;
    }
  }

  void _onCollapseTick() {
    final want = (_progress?.value ?? 1) < 1.0;
    if (want != _mirror && mounted) setState(() => _mirror = want);
  }

  @override
  void dispose() {
    _progress?.removeListener(_onCollapseTick);
    for (final c in _videoCtrls.values) {
      c.dispose();
    }
    _pageCtrl.dispose();
    _scroll.dispose();
    _commentCtrl.dispose();
    _commentsRev.dispose();
    super.dispose();
  }

  /// 페이지 전환 — 현재 페이지의 영상만 재생, 나머지는 일시정지.
  void _onPageChanged(int i) {
    setState(() => _page = i);
    _videoCtrls.forEach((idx, c) {
      if (idx == i) {
        if (c.value.isInitialized) c.play();
      } else {
        c.pause();
      }
    });
  }

  /// 딥링크 진입 후 내가 이 시설의 업주(개인 모드)면 업체 모드 전환을 제안한다.
  Future<void> _maybeSuggestSwitch() async {
    final ok = await BusinessRepository.instance.shouldSuggestBusinessSwitch(
      _reviewId!,
    );
    if (!ok || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('업체 모드로 전환할까요?'),
        content: const Text(
          '내 업체에 달린 후기예요. 업체 모드로 전환하면 상호(업체 얼굴)로 '
          '댓글을 남길 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('개인으로 볼게요'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('업체 모드로 전환'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final res = await BusinessRepository.instance.switchMode('business');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res == 'business' ? '업체 모드로 전환했어요' : '전환에 실패했어요')),
    );
  }

  // ── 댓글 ──

  /// 시트(별도 라우트)에도 최신 상태를 반영.
  void _syncSheet() => _commentsRev.value++;

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    _syncSheet();
    try {
      final list = await FacilityReviewRepository.instance.fetchComments(
        _reviewId!,
      );
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loadingComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingComments = false);
    }
    _syncSheet();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _syncSheet();
    try {
      await FacilityReviewRepository.instance.addComment(_reviewId!, text);
      _commentCtrl.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      await _loadComments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('댓글 작성에 실패했어요')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _syncSheet();
    }
  }

  /// 내 댓글 길게 누르기 → 삭제(소프트).
  Future<void> _confirmDeleteComment(FacilityReviewComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('댓글을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('삭제', style: TextStyle(color: dialogCtx.colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FacilityReviewRepository.instance.deleteComment(c.id);
      await _loadComments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제에 실패했어요')));
    }
  }

  /// 댓글 바텀시트 — 게시글과 동일한 공용 셸(배리어 off·포커스 중 드래그 잠금).
  /// 열람은 게스트도 가능, 입력바는 로그인 시에만.
  void _openComments() {
    if (_reviewId == null) return;
    showCommentsSheet<void>(
      context,
      builder: (_) => CommentsSheetShell(
        listenable: _commentsRev,
        title: () => '댓글 ${_comments.length}',
        inputController: _commentCtrl,
        sending: () => _sending,
        onSend: _sendComment,
        showInput: _loggedIn,
        listBuilder: (_) => _ReviewCommentList(
          loading: _loadingComments,
          comments: _comments,
          onDelete: _confirmDeleteComment,
          onOpenProfile: _openAuthorProfile,
        ),
      ),
    );
  }

  /// 내 후기 삭제 — 확인 후 제공자 콜백(삭제 API + 목록 갱신) 실행, 성공 시 닫기.
  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('후기를 삭제할까요?'),
        content: const Text('삭제한 후기는 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('삭제', style: TextStyle(color: dialogCtx.colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final deleted = await widget.review.onDelete!();
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제에 실패했어요. 잠시 후 다시 시도해주세요')),
      );
    }
  }

  /// 작성자/댓글 닉네임 탭 → 프로필. 앱 공통 상세 언어 — 아래에서 떠오르고,
  /// 쓸어내리면 닫힌다. [business] 는 업체 얼굴로 열지 여부(업체 모드 댓글).
  void _openAuthorProfile(
    String userId,
    String nickname, {
    required bool business,
  }) {
    Navigator.push(
      context,
      CollapseRoute(
        builder: (_) => UserProfileScreen(
          userId: userId,
          previewNickname: nickname,
          forcePersonalFace: !business,
          originRect: riseOriginRect(context),
          cardRadius: 24,
        ),
      ),
    );
  }

  /// 카드 복귀는 전환이 끝나기 전에 빠르게, 풀스크린 안착은 여유 있게.
  Duration get _anchorDuration => Duration(milliseconds: _mirror ? 150 : 380);

  @override
  Widget build(BuildContext context) {
    // 게시글 상세와 동일 — 테마 밝기 기준 상태바 아이콘 유지, 어두운 미디어 위
    // 가독성은 상단의 밝은 스크림이 담당.
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: CollapsibleView(
        originRect: widget.originRect,
        card: widget.cardBuilder,
        cardRadius: 14, // _ReviewCard 와 동일 곡률
        scrollController: _scroll,
        builder: (context, physics) => Scaffold(
          // 투명 — 축소 전환 중 카드 아래로 뒤 화면이 비친다(게시글과 동일).
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            // 뒤로가기 버튼 없음 — 아래로 당겨 카드로 축소(게시글 상세와 동일).
            automaticallyImplyLeading: false,
            actions: [
              // 내 후기만 삭제 가능(게시글 상세의 앱바 액션 문법).
              if (widget.review.isMine && widget.review.onDelete != null)
                OverlayIconButton(
                  icon: Icons.delete_outline,
                  tooltip: '내 후기 삭제',
                  color: const Color(0xFFFF8A80),
                  onPressed: _confirmDelete,
                ),
              const SizedBox(width: 8),
            ],
          ),
          // 쇼츠형 — 화면 = 전체화면 미디어 하나. 뷰포트 높이 1장짜리 리스트로
          // CollapsibleView 의 당겨서 축소하는 드래그 메커니즘만 보존.
          body: ListView(
            controller: _scroll,
            physics: physics,
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: MediaQuery.sizeOf(context).height,
                child: _hero(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    // 현재 페이지가 영상이면 그 컨트롤러의 재생 상태에 반응.
    final cur = _videoCtrls[_page];
    if (cur != null) {
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: cur,
        builder: (context, v, _) => _buildHero(context, v),
      );
    }
    return _buildHero(context, null);
  }

  Widget _buildHero(BuildContext context, VideoPlayerValue? v) {
    final r = widget.review;
    final hasMedia = _pages.isNotEmpty;
    final content = (r.content ?? '').trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 축소 전환 중엔 후기 그리드 타일과 같은 정사각(1:1) 상단 박스로.
        final boxH = _mirror ? w : h;
        final expanded = _expanded && !_mirror;
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final curIsVideo = _videoCtrls.containsKey(_page);
        return Stack(
          fit: StackFit.expand,
          children: [
            // 미디어 — 풀스크린 페이저, 축소 전환 중엔 정사각 상단 박스.
            AnimatedPositioned(
              duration: _anchorDuration,
              curve: Curves.easeOutCubic,
              top: 0,
              left: 0,
              right: 0,
              height: boxH,
              child: ClipRect(
                child: hasMedia
                    ? PageView(
                        controller: _pageCtrl,
                        onPageChanged: _onPageChanged,
                        children: [
                          for (var i = 0; i < _pages.length; i++)
                            _mediaPage(context, i),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          // 미디어 없는 후기 — 카드의 블롭 배경 + 본문 센터
                          // (게시글 블롭 글과 동일 문법, 탭으로 펼침/접힘).
                          BlobBackground(
                            seed:
                                r.seed ??
                                '${r.author}/${r.createdAt?.millisecondsSinceEpoch}',
                            color: context.colors.primary,
                          ),
                          Positioned.fill(
                            child: BlobHeroContent(
                              content: content.isEmpty ? '내용 없는 후기' : content,
                              mirror: false,
                              expanded: expanded,
                              expandedMaxHeight: h * 0.55,
                              anchorDuration: _anchorDuration,
                              onToggle: _mirror
                                  ? null
                                  : () =>
                                        setState(() => _expanded = !_expanded),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            // 하단 오버레이 패널 — 카드 미러 정보 + 그 뒤에만 σ8 사본 블러·스크림.
            // 후기 타일에는 이런 패널이 없으므로 축소 전환 중엔 페이드아웃.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _mirror ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: MediaOverlayPanel(
                  blurSource: _blurSource(context, v),
                  blurSourceSize: Size(w, boxH),
                  bottomClearance: safeBottom + (curIsVideo ? 24 : 10),
                  clearanceDuration: _anchorDuration,
                  child: _ReviewInfoOverlay(
                    review: r,
                    showContent: hasMedia && content.isNotEmpty,
                    expanded: expanded,
                    expandedMaxHeight: h * 0.5,
                    onToggleExpand: _mirror
                        ? null
                        : () => setState(() => _expanded = !_expanded),
                    commentCount: _reviewId == null ? null : _comments.length,
                    onComments: _reviewId == null ? null : _openComments,
                    onAuthorTap:
                        (r.authorUserId == null || r.authorUserId!.isEmpty)
                        ? null
                        // 방문 후기는 개인 활동 — 항상 개인 얼굴.
                        : () => _openAuthorProfile(
                            r.authorUserId!,
                            r.author,
                            business: false,
                          ),
                  ),
                ),
              ),
            ),
            // 페이지 인디케이터(1/N) — 상단 중앙, 축소 전환 중 페이드아웃.
            if (_pages.length > 1)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _mirror ? 0 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x66000000),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '${_page + 1}/${_pages.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 재생 진행바 — 현재 페이지가 영상일 때만(게시글과 동일 문법).
            if (v != null && v.isInitialized && !_videoErrors.contains(_page))
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
                      _videoCtrls[_page]!,
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
            if (hasMedia)
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
    );
  }

  /// 페이지 하나 — 사진(cover) 또는 영상(현재 페이지만 자동재생, 탭 토글).
  Widget _mediaPage(BuildContext context, int i) {
    final page = _pages[i];
    final photo = page.photoUrl;
    if (photo != null) {
      return Image.network(
        photo,
        fit: BoxFit.cover,
        cacheWidth: 1200,
        errorBuilder: (_, _, _) =>
            ColoredBox(color: context.colors.surfaceMuted),
      );
    }
    final video = page.video!;
    final ctrl = _videoCtrls[i]!;
    if (_videoErrors.contains(i)) {
      return const ColoredBox(
        color: kVideoFallbackBg,
        child: Center(child: VideoErrorLabel()),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: ctrl,
      builder: (context, v, _) {
        // 세로·정방형은 cover(풀스크린), 가로 영상은 검정 위 contain.
        final fit = v.isInitialized && v.aspectRatio > 1 && !_mirror
            ? BoxFit.contain
            : BoxFit.cover;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black), // letterbox 여백
            if (v.isInitialized)
              FittedBox(
                fit: fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: v.size.width,
                  height: v.size.height,
                  child: VideoPlayer(ctrl),
                ),
              ),
            // 포스터 — 초기화 전 cover 로 채우고, 준비되면 페이드아웃.
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: v.isInitialized ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: video.thumbUrl != null
                    ? Image.network(
                        video.thumbUrl!,
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
                onTap: () => toggleVideoPlayback(ctrl),
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
        );
      },
    );
  }

  /// 패널 블러의 원본 사본 — 현재 페이지의 미디어와 동일한 서브트리.
  /// 블롭(미디어 없음)은 null — 카드처럼 블러 없이 스크림만.
  Widget? _blurSource(BuildContext context, VideoPlayerValue? v) {
    if (_pages.isEmpty) return null;
    final page = _pages[_page];
    final photo = page.photoUrl;
    if (photo != null) {
      // 사진 — 카드의 블러 사본과 동일(저해상 디코딩으로 충분).
      return Image.network(
        photo,
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    if (_videoErrors.contains(_page)) {
      return const ColoredBox(color: kVideoFallbackBg);
    }
    if (v != null && v.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          FittedBox(
            fit: v.aspectRatio > 1 && !_mirror ? BoxFit.contain : BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: v.size.width,
              height: v.size.height,
              child: VideoPlayer(_videoCtrls[_page]!),
            ),
          ),
        ],
      );
    }
    final thumb = page.video?.thumbUrl;
    return thumb != null
        ? Image.network(
            thumb,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: kVideoFallbackBg),
          )
        : const ColoredBox(color: kVideoFallbackBg);
  }
}

/// 후기 하단 정보 오버레이 — 게시글 카드 미러(PostCardInfoOverlay)와 같은
/// 타이포·간격을 후기 문법으로: 업체 혜택 배지(표시광고법 — 반드시 노출)·방문
/// 차수·날짜 행, 별점(제목 자리), 본문(탭 확장), 닉네임·댓글 행.
class _ReviewInfoOverlay extends StatelessWidget {
  final ReviewCardData review;
  final bool showContent;
  final bool expanded;
  final double? expandedMaxHeight;
  final VoidCallback? onToggleExpand;

  /// 댓글 수(null 이면 댓글 없음 — 아이콘 미표시).
  final int? commentCount;
  final VoidCallback? onComments;
  final VoidCallback? onAuthorTap;

  const _ReviewInfoOverlay({
    required this.review,
    required this.showContent,
    required this.expanded,
    this.expandedMaxHeight,
    this.onToggleExpand,
    this.commentCount,
    this.onComments,
    this.onAuthorTap,
  });

  /// 흰 필름 알약 위에서도 읽히는 진한 앰버(카드 이동 태그와 동일 톤).
  static const _warnDark = Color(0xFF8F6E2F);

  Widget _pill(String label, {required Color fg}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = review;
    final d = r.createdAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // 표시광고법: 경제적 이해관계 표시 — 항상 노출.
                    if (r.hasIncentive) _pill('업체 혜택 받고 작성한 후기', fg: _warnDark),
                    if (r.visitNo != null)
                      _pill(
                        '${r.visitNo}번째 방문',
                        fg: context.colors.primaryDark,
                      ),
                    if (r.isMine)
                      _pill('내 후기', fg: context.colors.textSecondary),
                  ],
                ),
              ),
              if (d != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${d.year}.${d.month}.${d.day}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xCCFFFFFF),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // 별점 — 게시글 제목 자리.
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Icon(
                  i < r.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 21,
                  color: i < r.rating
                      ? const Color(0xFFFFB300)
                      : Colors.white38,
                ),
              const SizedBox(width: 6),
              Text(
                '${r.rating}.0',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          if (showContent) ...[
            const SizedBox(height: 4),
            if (onToggleExpand == null)
              Text(
                r.content!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xE0FFFFFF),
                  height: 1.5,
                ),
              )
            else
              // 본문 탭 = 펼침/접힘(게시글과 동일 — 블러 패널이 함께 자란다).
              ExpandableOverlayText(
                content: r.content!,
                previewLines: 2,
                expanded: expanded,
                expandedMaxHeight: expandedMaxHeight,
                onToggle: onToggleExpand!,
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              // 닉네임 탭 → 작성자 프로필(게시글 오버레이와 동일 문법).
              GestureDetector(
                onTap: onAuthorTap,
                child: Text(
                  r.author,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xE6FFFFFF),
                  ),
                ),
              ),
              const Spacer(),
              if (commentCount != null)
                GestureDetector(
                  onTap: onComments,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 16,
                        color: Color(0xCCFFFFFF),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$commentCount',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xCCFFFFFF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 후기 댓글 리스트(시트 본문) — 로딩/빈 상태/행. 내 댓글 길게 누르면 삭제,
/// 닉네임 탭 → 프로필(업체 모드 댓글은 업체 얼굴).
class _ReviewCommentList extends StatelessWidget {
  final bool loading;
  final List<FacilityReviewComment> comments;
  final void Function(FacilityReviewComment) onDelete;
  final void Function(String userId, String nickname, {required bool business})
  onOpenProfile;

  const _ReviewCommentList({
    required this.loading,
    required this.comments,
    required this.onDelete,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (comments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: context.colors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            '첫 댓글을 남겨보세요',
            style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final c in comments)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: c.isMine ? () => onDelete(c) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: c.userId.isEmpty
                            ? null
                            : () => onOpenProfile(
                                c.userId,
                                c.authorNickname,
                                business: c.authoredAs == 'business',
                              ),
                        child: Text(
                          c.authorNickname,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo(c.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.colors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
