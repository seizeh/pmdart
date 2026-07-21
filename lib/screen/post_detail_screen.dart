import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import '../motion/motion.dart';
import '../services/business_repository.dart';
import 'user_profile_screen.dart';
import '../theme/app_palette.dart';
import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../models/community.dart';
import '../services/community_repository.dart';
import '../services/social_repository.dart';
import '../services/chat_launcher.dart';
import '../services/report_repository.dart';
import '../services/session.dart';
import '../widgets/blob_background.dart';
import '../widgets/overlay_icon_button.dart';
import '../widgets/role_badge.dart';
import '../widgets/report_sheet.dart';
import 'auth/auth_wall_dialog.dart';
import 'applicants_screen.dart';
import 'post_edit_screen.dart';

/// 신고 액션 시트의 한 항목.
class _ReportAction {
  final String label;
  final VoidCallback onTap;
  const _ReportAction(this.label, this.onTap);
}

/// 게시글 상세 — 본문 / 약속·위치 / 작성자 / 댓글(실데이터) / 하트·지원·댓글 작성.
class PostDetailScreen extends StatefulWidget {
  final Post post;
  final bool isGuest;

  /// 피드 카드에서 펼쳐지고/카드로 축소되는 인터랙션용. null 이면 일반 화면.
  final Rect? originRect;

  /// 축소 시 크로스페이드로 나타날 실제 커뮤니티 카드(피드와 동일 위젯).
  final WidgetBuilder? cardBuilder;

  /// 원본 카드의 모서리 곡률 — 축소 안착 시 곡률이 튀지 않도록 카드와 맞춘다.
  final double cardRadius;

  /// 이 화면으로 들어오기 직전에 보던 사용자 프로필의 id(있으면). 작성자가 그
  /// 사용자면 닉네임 탭이 새 프로필을 쌓지 않고 pop 으로 되돌아간다
  /// (프로필→게시글→작성자→프로필… 무한 스택 방지 — 펫↔보호자와 동일 패턴).
  final String? fromUserId;

  const PostDetailScreen({
    super.key,
    required this.post,
    this.isGuest = false,
    this.originRect,
    this.cardBuilder,
    this.cardRadius = 20,
    this.fromUserId,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _repo = CommunityRepository.instance;
  final _commentCtrl = TextEditingController();

  late Post _post;
  List<Comment> _comments = [];
  bool _loadingComments = true;
  bool _sending = false;
  bool _applying = false;
  bool _following = false;

  // 본문 최상단에서 아래로 당기면 카드로 축소되는 CollapsibleView 용 스크롤 컨트롤러.
  final _scroll = ScrollController();

  /// 지원자 목록을 관리(조회·수락)할 수 있는지 — 작성자 또는 공동보호자.
  bool _canManage = false;

  /// 공동보호자 권한 확인이 끝났는지 (확인 전엔 지원하기 버튼을 숨긴다).
  bool _managerChecked = false;

  /// 현재 업체 모드인가 — 업체 모드에선 지원(개인 매칭)이 불가하므로 버튼을
  /// 숨기고 안내로 대체한다(서버 트리거가 최종 방어선).
  bool _businessMode = false;

  /// 매칭(지원→약속) 없는 게시글 — 자유글·업체 소식. 지원 UI 를 띄우지 않는다.
  bool get _isFreePost => _post.category == 'free' || _post.category == 'news';
  bool get _isMyPost => _post.userId == SessionManager.instance.user?.id;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    // 작성자는 즉시 관리자, 그 외 사용자는 공동보호자 여부를 서버에 확인한다.
    _canManage = _isMyPost;
    _managerChecked = _isMyPost || widget.isGuest || _isFreePost;
    _loadComments();
    // 작성자 본인 조회는 조회수에 반영하지 않는다.
    if (!widget.isGuest && !_isMyPost) {
      _recordView();
      _loadFollowing();
      if (!_isFreePost) {
        _loadManager();
        _loadMode();
      }
    }
  }

  Future<void> _loadMode() async {
    try {
      final mode = await BusinessRepository.instance.fetchActiveMode();
      if (mounted) setState(() => _businessMode = mode == 'business');
    } catch (_) {}
  }

  /// 조회수 기록 (같은 시간대 재조회는 집계 안 됨). 집계됐으면 화면 수치도 +1.
  Future<void> _recordView() async {
    final counted = await _repo.recordView(_post.id);
    if (counted && mounted) {
      setState(() => _post = _post.copyWith(viewCount: _post.viewCount + 1));
    }
  }

  Future<void> _loadManager() async {
    try {
      final can = await _repo.canManageApplicants(_post.id);
      if (mounted) {
        setState(() {
          _canManage = can;
          _managerChecked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _managerChecked = true);
    }
  }

  Future<void> _loadFollowing() async {
    try {
      // 글의 얼굴(개인/업체) 단위로 팔로우 상태 확인 — 업체 글은 업체 팔로우 여부.
      final f = await SocialRepository.instance.isFollowing(
        _post.userId,
        business: _post.authoredAs == 'business',
      );
      if (mounted) setState(() => _following = f);
    } catch (_) {}
  }

  // 실수 이중 탭(팔로우→즉시 언팔) 방지 쿨다운 — 프로필 화면과 동일 규칙.
  DateTime? _lastFollowToggle;

  Future<void> _toggleFollow() async {
    if (!_guard('팔로우는 로그인 후 할 수 있어요')) return;
    final now = DateTime.now();
    if (_lastFollowToggle != null &&
        now.difference(_lastFollowToggle!) <
            const Duration(milliseconds: 700)) {
      return;
    }
    _lastFollowToggle = now;
    final was = _following;
    setState(() => _following = !was);
    try {
      // 팔로우/해제 모두 글의 얼굴 단위 — 업체 글(소식)은 업체 팔로우로.
      final biz = _post.authoredAs == 'business';
      if (was) {
        await SocialRepository.instance.unfollow(_post.userId, business: biz);
      } else {
        await SocialRepository.instance.follow(_post.userId, business: biz);
      }
    } catch (_) {
      if (mounted) setState(() => _following = was);
    }
  }

  void _startChat() {
    if (!_guard('채팅은 로그인 후 이용할 수 있어요')) return;
    openDirectChat(context, _post.userId);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list = await _repo.fetchComments(_post.id);
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

  bool _guard(String message) {
    if (widget.isGuest) {
      AuthWallDialog.show(context, message: message);
      return false;
    }
    return true;
  }

  Future<void> _toggleHeart() async {
    if (!_guard('하트는 로그인 후 누를 수 있어요')) return;
    final wasHearted = _post.hearted;
    // 낙관적 업데이트
    setState(
      () => _post = _post.copyWith(
        hearted: !wasHearted,
        heartCount: _post.heartCount + (wasHearted ? -1 : 1),
      ),
    );
    try {
      await _repo.toggleHeart(_post.id, wasHearted);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _post = _post.copyWith(
          hearted: wasHearted,
          heartCount: _post.heartCount + (wasHearted ? 1 : -1),
        ),
      );
      _toast('잠시 후 다시 시도해주세요');
    }
  }

  Future<void> _sendComment() async {
    if (!_guard('댓글은 로그인 후 작성할 수 있어요')) return;
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.addComment(_post.id, text);
      _commentCtrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
      await _loadComments();
    } catch (_) {
      _toast('댓글 작성에 실패했어요');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _apply() async {
    if (!_guard('지원은 로그인 후 할 수 있어요')) return;
    // 매칭(지원→약속→평가)은 실제 만남 전제의 개인 활동 — 업체 모드에선 차단하고
    // 일반 모드 전환을 유도한다(서버 트리거가 최종 방어선, 0026 §5-2).
    final mode = await BusinessRepository.instance.fetchActiveMode();
    if (!mounted) return;
    if (mode == 'business') {
      final switched = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: const Text('업체 모드에서는 지원할 수 없어요'),
          content: const Text(
            '산책·돌봄 매칭은 일반 모드에서 이용할 수 있어요.\n일반 모드로 전환하고 지원할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('전환하고 지원'),
            ),
          ],
        ),
      );
      if (switched != true || !mounted) return;
      final result = await BusinessRepository.instance.switchMode('personal');
      if (!mounted) return;
      if (result != 'personal') {
        _toast('모드 전환에 실패했어요. 잠시 후 다시 시도해주세요');
        return;
      }
      _toast('일반 모드로 전환했어요');
    }
    setState(() => _applying = true);
    try {
      await _repo.apply(_post.id);
      _toast('지원했어요');
    } catch (e) {
      _toast('이미 지원했거나 지원할 수 없는 게시글이에요');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _openApplicants() {
    Navigator.push(
      context,
      AppPageRoute(builder: (_) => ApplicantsScreen(post: _post)),
    );
  }

  /// 내 게시글 수정 → 저장되면 최신 내용으로 다시 불러온다.
  Future<void> _openEdit() async {
    final saved = await Navigator.push<bool>(
      context,
      AppPageRoute(builder: (_) => PostEditScreen(post: _post)),
    );
    if (saved == true) {
      final fresh = await _repo.fetchPost(_post.id);
      if (!mounted) return;
      if (fresh == null) {
        // 수정 화면에서 삭제됨 → 상세도 닫는다(축소 전환 경유).
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _post = fresh);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 게시글 상단 메뉴 — 게시글/작성자 신고(본인 글은 메뉴 미노출).
  void _openPostMenu() {
    if (!_guard('신고는 로그인 후 할 수 있어요')) return;
    _showReportActions([
      _ReportAction(
        '게시글 신고',
        () =>
            _report(ReportRepository.targetPost, _post.id, '게시글', _post.title),
      ),
      _ReportAction(
        '작성자 신고',
        () => _report(
          ReportRepository.targetUser,
          _post.userId,
          '작성자',
          _post.authorNickname,
        ),
      ),
    ]);
  }

  /// 댓글 길게 누르기 — 댓글/작성자 신고(본인 댓글은 호출 안 됨).
  void _openCommentMenu(Comment c) {
    if (!_guard('신고는 로그인 후 할 수 있어요')) return;
    _showReportActions([
      _ReportAction(
        '댓글 신고',
        () => _report(ReportRepository.targetComment, c.id, '댓글', c.content),
      ),
      _ReportAction(
        '작성자 신고',
        () => _report(
          ReportRepository.targetUser,
          c.userId,
          '작성자',
          c.authorNickname,
        ),
      ),
    ]);
  }

  void _showReportActions(List<_ReportAction> actions) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                leading: Icon(
                  Icons.flag_outlined,
                  color: context.colors.danger,
                ),
                title: Text(a.label),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  a.onTap();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(
    String type,
    String id,
    String label,
    String title,
  ) async {
    final ok = await showReportSheet(
      context,
      targetType: type,
      targetId: id,
      targetLabel: label,
      targetTitle: title,
    );
    if (ok && mounted) _toast('신고가 접수되었어요. 검토 후 조치할게요');
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _post.imageUrl != null;

    // 카드에서 펼쳐지고/아래로 당기면 카드로 축소되는 공통 래퍼. physics 를 리스트에 전달.
    // AnnotatedRegion — 사진 유무와 무관하게 전역 기본과 같은 테마 밝기 기준
    // 상태바 아이콘 유지(사진 글에서 시간·배터리가 흰색으로 바뀌던 문제 해결).
    // 어두운 사진 위 가독성은 히어로 상단의 밝은 스크림이 담당한다.
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: CollapsibleView(
        originRect: widget.originRect,
        card: widget.cardBuilder,
        cardRadius: widget.cardRadius,
        scrollController: _scroll,
        builder: (context, physics) => Scaffold(
          backgroundColor: context.colors.background,
          // 히어로(사진 또는 블롭 본문)가 상태바까지 차오르도록 앱바를 투명 오버레이로.
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            // 뒤로가기 버튼 없음 — 아래로 당겨 카드로 축소하거나 시스템 뒤로가기
            // (프로필·펫 상세와 동일한 몰입형).
            automaticallyImplyLeading: false,
            actions: [
              if (_isMyPost)
                OverlayIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: '수정',
                  onPressed: _openEdit,
                ),
              if (!_isMyPost)
                OverlayIconButton(
                  icon: Icons.chat_bubble_outline,
                  tooltip: '채팅하기',
                  onPressed: _startChat,
                ),
              if (!_isMyPost)
                OverlayIconButton(
                  icon: Icons.report_outlined,
                  tooltip: '신고',
                  color: const Color(0xFFFF8A80),
                  onPressed: _openPostMenu,
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            controller: _scroll,
            physics: physics, // 드래그 중 잠금은 CollapsibleView 가 제공
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // 히어로 — 피드 카드와 동일 비율. 사진 글은 대표사진,
              // 사진 없는 글은 카드와 같은 블롭 배경 + 본문(같은 위치/스타일)로
              // 축소 전환 시 피드 카드와 그대로 겹쳐진다.
              AspectRatio(
                aspectRatio: kPostImageAspectRatio,
                child: hasImage
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            _post.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: context.colors.surfaceMuted),
                          ),
                          // 상태바 스크림 — 어두운 사진에서도 시간·배터리(어두운
                          // 아이콘)가 읽히도록 사진 위쪽만 옅게 밝힌다.
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
                                    colors: [
                                      Colors.white70,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : _BlobHero(post: _post),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _infoChildren(contentInHero: !hasImage),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _BottomBar(
            post: _post,
            controller: _commentCtrl,
            sending: _sending,
            onHeart: _toggleHeart,
            onSend: _sendComment,
          ),
        ),
      ),
    );
  }

  /// 히어로에 본문이 다 담겼는지(9줄·짧은 글). 넘치면 아래에 전문을 보여준다.
  bool get _heroHoldsFullContent {
    final c = _post.content;
    return c.length <= 180 && '\n'.allMatches(c).length < 9;
  }

  /// 본문 정보 위젯들(카테고리 칩부터 댓글까지).
  /// [contentInHero] 가 true(사진 없는 글)면 본문이 상단 히어로에 있으므로,
  /// 히어로에서 잘리는 긴 글에만 전문을 아래에 덧붙인다.
  List<Widget> _infoChildren({required bool contentInHero}) {
    final color = categoryColor(context, _post.category);
    final showContent = !contentInHero || !_heroHoldsFullContent;
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            categoryLabel(_post.category),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        _post.title,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          height: 1.3,
        ),
      ),
      const SizedBox(height: 14),
      _AuthorRow(
        post: _post,
        showFollow: !widget.isGuest && !_isMyPost,
        following: _following,
        onFollow: _toggleFollow,
        popInstead:
            widget.fromUserId != null && widget.fromUserId == _post.userId,
      ),
      if (showContent) ...[
        const SizedBox(height: 20),
        Divider(height: 1, color: context.colors.border),
        const SizedBox(height: 20),
        Text(
          _post.content,
          style: TextStyle(
            fontSize: 15,
            color: context.colors.textPrimary,
            height: 1.7,
          ),
        ),
      ],
      if (_post.scheduledAt != null || _post.location != null) ...[
        const SizedBox(height: 24),
        _InfoBox(post: _post),
      ],
      if (!_isFreePost && _canManage) ...[
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _openApplicants,
          icon: const Icon(Icons.people_outline),
          label: const Text('지원자 목록 보기'),
        ),
      ] else if (!_isFreePost &&
          _managerChecked &&
          _post.progressStatus == 'recruiting') ...[
        const SizedBox(height: 20),
        // 업체 모드에선 지원(개인 매칭) 불가 — 버튼 대신 안내.
        if (_businessMode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: context.colors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '업체 모드에서는 지원할 수 없어요.\n산책·돌봄 매칭은 일반 모드에서 이용해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: context.colors.textSecondary,
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _applying ? null : _apply,
            icon: _applying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('이 게시글에 지원하기'),
          ),
      ],
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
      _CommentList(
        loading: _loadingComments,
        comments: _comments,
        myUserId: SessionManager.instance.user?.id,
        onReport: _openCommentMenu,
      ),
    ];
  }
}

class _AuthorRow extends StatelessWidget {
  final Post post;
  final bool showFollow;
  final bool following;
  final VoidCallback onFollow;

  /// 직전 화면이 이 작성자의 프로필 — 새로 쌓지 않고 되돌아간다(무한 왕복 방지).
  final bool popInstead;

  const _AuthorRow({
    required this.post,
    required this.showFollow,
    required this.following,
    required this.onFollow,
    this.popInstead = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 닉네임 탭 → 작성자 프로필. 피드 카드의 닉네임과 동일한 모달 문법 —
            // 아래에서 떠오르고, 당기거나 뒤로가기 하면 아래로 내려가며 닫힌다.
            GestureDetector(
              onTap: post.userId.isEmpty
                  ? null
                  // 방금 그 프로필에서 왔으면 축소 애니메이션을 태워 되돌아간다.
                  : popInstead
                  ? () => Navigator.of(context).maybePop()
                  : () => Navigator.push(
                      context,
                      CollapseRoute(
                        builder: (_) => UserProfileScreen(
                          userId: post.userId,
                          previewNickname: post.authorNickname,
                          originRect: riseOriginRect(context),
                          cardRadius: 24,
                          // 프로필에서 이 게시글을 다시 열면 pop(무한 왕복 방지).
                          fromPostId: post.id,
                          // 작성 모드가 얼굴을 결정 — 개인 글 작성자는 개인 얼굴만
                          // (업체 글은 상호로 표시되고 업체 얼굴로 연다, 0025)
                          forcePersonalFace: post.authoredAs != 'business',
                        ),
                      ),
                    ),
              child: Text(
                post.authorNickname,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${timeAgo(post.createdAt)} · 조회 ${post.viewCount}${post.isEdited ? ' · 수정됨' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (showFollow) _FollowButton(following: following, onTap: onFollow),
      ],
    );
  }
}

/// 팔로우(Pawing) 토글 버튼.
class _FollowButton extends StatelessWidget {
  final bool following;
  final VoidCallback onTap;
  const _FollowButton({required this.following, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: following
              ? context.colors.surface
              : context.colors.primaryDark,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: following
                ? context.colors.border
                : context.colors.primaryDark,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              following ? Icons.check : Icons.add,
              size: 14,
              color: following
                  ? context.colors.textSecondary
                  : context.colors.textOnPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              following ? 'Pawing 중' : 'Pawing',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: following
                    ? context.colors.textSecondary
                    : context.colors.textOnPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final Post post;
  const _InfoBox({required this.post});

  // 약속 일정 — 연도 생략·오전/오후 12시제로 짧게(한 줄에 들어가게).
  static String _formatSchedule(DateTime d) {
    final ampm = d.hour < 12 ? '오전' : '오후';
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute == 0 ? '' : ' ${d.minute}분';
    return '${d.month}월 ${d.day}일 $ampm $h12시$min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: Column(
        children: [
          if (post.scheduledAt != null)
            _row(
              context,
              Icons.event_outlined,
              '약속 일정',
              _formatSchedule(post.scheduledAt!),
            ),
          if (post.scheduledAt != null && post.location != null)
            const SizedBox(height: 12),
          if (post.location != null)
            _row(context, Icons.place_outlined, '위치', post.location!),
          if (post.authorMoved) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: context.colors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '작성자가 현재 다른 지역에 있어요.\n위 위치는 작성 당시 활동 동네예요.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: context.colors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Row(
    children: [
      Icon(icon, size: 18, color: context.colors.primaryDark),
      const SizedBox(width: 10),
      Text(
        label,
        style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
      ),
      const SizedBox(width: 12),
      // 값은 남은 폭을 모두 차지하고 우측 정렬 — 한 줄 유지(넘치면 …).
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    ],
  );
}

class _CommentList extends StatelessWidget {
  final bool loading;
  final List<Comment> comments;

  /// 본인 댓글은 신고 대상에서 제외하기 위한 현재 사용자 id.
  final String? myUserId;

  /// 댓글 길게 누르기 신고 콜백.
  final void Function(Comment) onReport;
  const _CommentList({
    required this.loading,
    required this.comments,
    required this.myUserId,
    required this.onReport,
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
      children: comments.map((c) {
        final isMine = myUserId != null && c.userId == myUserId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: isMine ? null : () => onReport(c),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // 닉네임 탭 → 작성자 프로필(아래에서 떠오르고 쓸어내려 닫기).
                          GestureDetector(
                            onTap: c.userId.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    CollapseRoute(
                                      builder: (_) => UserProfileScreen(
                                        userId: c.userId,
                                        previewNickname: c.authorNickname,
                                        // 업체 모드 댓글(상호 표시)만 업체 얼굴.
                                        forcePersonalFace:
                                            c.authoredAs != 'business',
                                        originRect: riseOriginRect(context),
                                        cardRadius: 24,
                                      ),
                                    ),
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
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final Post post;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onHeart;
  final VoidCallback onSend;

  const _BottomBar({
    required this.post,
    required this.controller,
    required this.sending,
    required this.onHeart,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
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
        // viewInsets 를 자동 반영하지 않아 직접 더한다(후기 상세와 동일 수정).
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onHeart,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      post.hearted ? Icons.favorite : Icons.favorite_border,
                      color: post.hearted
                          ? context.colors.danger
                          : context.colors.textSecondary,
                    ),
                    Text(
                      '${post.heartCount}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
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
                  icon: sending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.textOnPrimary,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward,
                          color: context.colors.textOnPrimary,
                        ),
                  onPressed: sending ? null : onSend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 사진 없는 글의 상단 히어로 — 피드 카드와 동일한 블롭·본문 배치로 전환을 잇고,
/// 확장이 끝나면 본문을 히어로 정중앙으로 살짝 내려 앉힌다. 축소(드래그/뒤로가기)가
/// 시작되면 즉시 카드 위치(하단 정보 여백 170)로 되돌려 피드 카드와 겹치게 한다.
class _BlobHero extends StatefulWidget {
  final Post post;
  const _BlobHero({required this.post});

  @override
  State<_BlobHero> createState() => _BlobHeroState();
}

class _BlobHeroState extends State<_BlobHero> {
  Animation<double>? _progress;
  bool _centered = false; // true=히어로 정중앙, false=피드 카드와 동일 배치
  bool _initialized = false;

  void _onTick() {
    final want = (_progress?.value ?? 1) >= 1.0;
    if (want != _centered && mounted) setState(() => _centered = want);
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
      // 전환 없이 열린 화면(비확장 진입)은 처음부터 중앙 정렬.
      _centered = (p?.value ?? 1) >= 1.0;
    }
  }

  @override
  void dispose() {
    _progress?.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BlobBackground(
          seed: widget.post.id,
          color: categoryColor(context, widget.post.category),
        ),
        Positioned.fill(
          child: AnimatedPadding(
            // 내려앉기는 여유 있게, 축소 복귀는 전환이 끝나기 전에 빠르게.
            duration: Duration(milliseconds: _centered ? 380 : 150),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(22, 24, 22, _centered ? 24 : 170),
            child: Center(
              child: Text(
                widget.post.content,
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
}
