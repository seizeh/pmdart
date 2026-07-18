import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/mock_data.dart' show timeAgo;
import '../models/community.dart' show kPostImageAspectRatio;
import '../models/facility_review.dart';
import '../motion/motion.dart';
import '../services/business_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/session.dart';
import '../theme/app_palette.dart';
import '../widgets/blob_background.dart';
import '../widgets/overlay_icon_button.dart';
import '../widgets/review_cards.dart';
import 'user_profile_screen.dart';

/// 시설 방문 후기 상세 — 게시글 상세와 동일한 문법.
///
/// 후기 카드 자리에서 펼쳐지고(originRect), 최상단에서 아래로 당기면 카드로
/// 축소되며 닫힌다(CollapsibleView). 히어로는 사진 후기면 대표 사진,
/// 사진 없는 후기면 카드와 같은 블롭 배경 + 본문(축소 시 카드와 겹쳐 안착).
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

class _ReviewDetailScreenState extends State<ReviewDetailScreen> {
  final _scroll = ScrollController();

  // 댓글 — reviewId 가 있는 후기(시설 후기)에만 붙는다.
  final _commentCtrl = TextEditingController();
  List<FacilityReviewComment> _comments = [];
  bool _loadingComments = false;
  bool _sending = false;

  String? get _reviewId => widget.review.reviewId;
  bool get _loggedIn => SessionManager.instance.user != null;

  @override
  void initState() {
    super.initState();
    if (_reviewId != null) _loadComments();
    if (widget.fromDeepLink && _reviewId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSuggestSwitch());
    }
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
      SnackBar(
        content: Text(
          res == 'business' ? '업체 모드로 전환했어요' : '전환에 실패했어요',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
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
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await FacilityReviewRepository.instance.addComment(_reviewId!, text);
      _commentCtrl.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      await _loadComments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 작성에 실패했어요')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제에 실패했어요')),
      );
    }
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

  /// 히어로(블롭)에 본문이 다 담겼는지 — 게시글 상세와 같은 기준(9줄·짧은 글).
  bool get _heroHoldsFullContent {
    final c = widget.review.content ?? '';
    return c.length <= 180 && '\n'.allMatches(c).length < 9;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final hasPhoto = r.photoUrls.isNotEmpty;

    // 게시글 상세와 동일 — 테마 밝기 기준 상태바 아이콘 유지, 어두운 사진 위
    // 가독성은 히어로 상단의 밝은 스크림이 담당.
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
          backgroundColor: context.colors.background,
          extendBodyBehindAppBar: true,
          // 댓글 입력 바 — 시설 후기(reviewId 보유) + 로그인 상태에서만.
          bottomNavigationBar: (_reviewId != null && _loggedIn)
              ? _commentInputBar()
              : null,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            // 뒤로가기 버튼 없음 — 아래로 당겨 카드로 축소(게시글 상세와 동일).
            automaticallyImplyLeading: false,
            actions: [
              // 내 후기만 삭제 가능(게시글 상세의 앱바 액션 문법).
              if (r.isMine && r.onDelete != null)
                OverlayIconButton(
                  icon: Icons.delete_outline,
                  tooltip: '내 후기 삭제',
                  color: const Color(0xFFFF8A80),
                  onPressed: _confirmDelete,
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            controller: _scroll,
            physics: physics,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              AspectRatio(
                aspectRatio: kPostImageAspectRatio,
                child: hasPhoto ? _photoHero(r) : _blobHero(r),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _infoChildren(r, contentInHero: !hasPhoto),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoHero(ReviewCardData r) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          r.photoUrls.first,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              ColoredBox(color: context.colors.surfaceMuted),
        ),
        // 상태바 스크림 — 어두운 사진에서도 시간·배터리가 읽히게(게시글과 동일).
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
  }

  /// 사진 없는 후기 — 카드와 같은 블롭 배경 + 본문. 축소 시 카드와 겹쳐진다.
  Widget _blobHero(ReviewCardData r) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BlobBackground(
          seed: r.seed ?? '${r.author}/${r.createdAt?.millisecondsSinceEpoch}',
          color: context.colors.primary,
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Center(
              child: Text(
                (r.content ?? '').isEmpty ? '내용 없는 후기' : r.content!,
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
      ],
    );
  }

  /// 본문 정보 위젯들 — 게시글 상세의 칩→제목→작성자→본문 순서를 후기 문법으로:
  /// 방문 차수 칩 → 별점(제목 자리) → 작성자·날짜 → 본문 → 나머지 사진.
  List<Widget> _infoChildren(ReviewCardData r, {required bool contentInHero}) {
    final showContent = (r.content ?? '').isNotEmpty &&
        (!contentInHero || !_heroHoldsFullContent);
    return [
      if (r.visitNo != null || r.isMine)
        Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.visitNo != null)
                _chip(
                  '${r.visitNo}번째 방문',
                  fg: context.colors.primaryDark,
                  bg: context.colors.primary.withValues(alpha: 0.12),
                ),
              if (r.visitNo != null && r.isMine) const SizedBox(width: 6),
              if (r.isMine)
                _chip(
                  '내 후기',
                  fg: context.colors.textSecondary,
                  bg: context.colors.surfaceMuted,
                ),
            ],
          ),
        ),
      if (r.visitNo != null || r.isMine) const SizedBox(height: 14),
      // 별점 — 게시글의 제목 자리.
      Row(
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              i < r.rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 26,
              color: i < r.rating
                  ? const Color(0xFFFFB300)
                  : context.colors.border,
            ),
          const SizedBox(width: 8),
          Text(
            '${r.rating}.0',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      // 작성자 행 — 닉네임 + 작성일(팔로우 등은 후기에 없음).
      // 닉네임 탭 → 작성자 프로필(아래에서 떠오르고 쓸어내려 닫기).
      Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: (r.authorUserId == null || r.authorUserId!.isEmpty)
                  ? null
                  : () => _openAuthorProfile(
                      r.authorUserId!,
                      r.author,
                      // 방문 후기는 개인 활동 — 항상 개인 얼굴.
                      business: false,
                    ),
              child: Text(
                r.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
          if (r.createdAt != null)
            Text(
              '${r.createdAt!.year}.${r.createdAt!.month}.${r.createdAt!.day}',
              style: TextStyle(
                fontSize: 12.5,
                color: context.colors.textTertiary,
              ),
            ),
        ],
      ),
      if (showContent) ...[
        const SizedBox(height: 20),
        Divider(height: 1, color: context.colors.border),
        const SizedBox(height: 20),
        Text(
          r.content!,
          style: TextStyle(
            fontSize: 15,
            color: context.colors.textPrimary,
            height: 1.7,
          ),
        ),
      ],
      // 나머지 사진(히어로에 쓴 첫 장 제외) — 본문 아래에 이어서.
      for (final url in r.photoUrls.skip(1)) ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ],
      // 댓글 — 게시글 상세와 동일 문법(목록 + 하단 입력 바).
      if (_reviewId != null) ...[
        const SizedBox(height: 28),
        Text(
          '댓글 ${_comments.length}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _commentSection(),
      ],
    ];
  }

  Widget _commentSection() {
    if (_loadingComments) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_comments.isEmpty) {
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
        for (final c in _comments)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: c.isMine ? () => _confirmDeleteComment(c) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 닉네임 탭 → 작성자 프로필(업체 모드 댓글은 업체 얼굴로).
                      GestureDetector(
                        onTap: c.userId.isEmpty
                            ? null
                            : () => _openAuthorProfile(
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

  /// 하단 댓글 입력 바 — 게시글 상세 _BottomBar 의 입력부와 동일 문법(하트 없음).
  Widget _commentInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(color: context.colors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        // 키보드가 올라오면 입력바가 그 위로 붙게 — bottomNavigationBar 는
        // viewInsets 를 자동 반영하지 않아 직접 더한다(입력 내용이 가려지던 문제).
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: '댓글을 입력하세요',
                    filled: true,
                    fillColor: context.colors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide(
                        color: context.colors.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                decoration: BoxDecoration(
                  color: context.colors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: _sending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.textOnPrimary,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          color: context.colors.textOnPrimary,
                        ),
                  onPressed: _sending ? null : _sendComment,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, {required Color fg, required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
