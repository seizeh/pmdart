import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import '../motion/motion.dart';
import '../theme/app_colors.dart';
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

  const PostDetailScreen({
    super.key,
    required this.post,
    this.isGuest = false,
    this.originRect,
    this.cardBuilder,
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

  bool get _isFreePost => _post.category == 'free';
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
      if (!_isFreePost) _loadManager();
    }
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
      final f = await SocialRepository.instance.isFollowing(_post.userId);
      if (mounted) setState(() => _following = f);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (!_guard('팔로우는 로그인 후 할 수 있어요')) return;
    final was = _following;
    setState(() => _following = !was);
    try {
      if (was) {
        await SocialRepository.instance.unfollow(_post.userId);
      } else {
        await SocialRepository.instance.follow(_post.userId);
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
      if (fresh != null && mounted) setState(() => _post = fresh);
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: AppColors.danger,
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
    // AnnotatedRegion — 사진 히어로는 밝은 상태바 아이콘, 벗어나면 자동으로
    // 전역 기본(어두움)으로 복원(흰 화면에서 아이콘이 안 보이던 문제 해결).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: hasImage
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: CollapsibleView(
      originRect: widget.originRect,
      card: widget.cardBuilder,
      scrollController: _scroll,
      builder: (context, physics) => Scaffold(
        backgroundColor: Colors.white,
        // 히어로(사진 또는 블롭 본문)가 상태바까지 차오르도록 앱바를 투명 오버레이로.
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: OverlayIconButton(
            icon: Icons.arrow_back,
            tooltip: '뒤로',
            onPressed: () => Navigator.maybePop(context),
          ),
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
                  ? Image.network(
                      _post.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: AppColors.surfaceMuted),
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
    final color = categoryColor(_post.category);
    final showContent = !contentInHero || !_heroHoldsFullContent;
    return [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              _AuthorRow(
                post: _post,
                showFollow: !widget.isGuest && !_isMyPost,
                following: _following,
                onFollow: _toggleFollow,
              ),
              if (showContent) ...[
                const SizedBox(height: 20),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 20),
                Text(
                  _post.content,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
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
  const _AuthorRow({
    required this.post,
    required this.showFollow,
    required this.following,
    required this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.authorNickname,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${timeAgo(post.createdAt)} · 조회 ${post.viewCount}${post.isEdited ? ' · 수정됨' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
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
          color: following ? AppColors.surface : AppColors.primaryDark,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: following ? AppColors.border : AppColors.primaryDark,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              following ? Icons.check : Icons.add,
              size: 14,
              color: following
                  ? AppColors.textSecondary
                  : AppColors.textOnPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              following ? 'Pawing 중' : 'Pawing',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: following
                    ? AppColors.textSecondary
                    : AppColors.textOnPrimary,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          if (post.scheduledAt != null)
            _row(
              Icons.event_outlined,
              '약속 일정',
              '${post.scheduledAt!.year}년 ${post.scheduledAt!.month}월 ${post.scheduledAt!.day}일 ${post.scheduledAt!.hour}시',
            ),
          if (post.scheduledAt != null && post.location != null)
            const SizedBox(height: 12),
          if (post.location != null)
            _row(Icons.place_outlined, '위치', post.location!),
          if (post.authorMoved) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '작성자가 현재 다른 지역에 있어요.\n위 위치는 작성 당시 활동 동네예요.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.warning,
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

  Widget _row(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.primaryDark),
      const SizedBox(width: 10),
      Text(
        label,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      const Spacer(),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
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
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            '첫 댓글을 남겨보세요',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
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
                          Text(
                            c.authorNickname,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeAgo(c.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c.content,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
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
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                          ? AppColors.danger
                          : AppColors.textSecondary,
                    ),
                    Text(
                      '${post.heartCount}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
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
                    fillColor: AppColors.surfaceMuted,
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
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnPrimary,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward,
                          color: AppColors.textOnPrimary,
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
          color: categoryColor(widget.post.category),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
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

