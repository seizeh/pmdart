import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../models/community.dart';
import '../services/community_repository.dart';
import '../services/social_repository.dart';
import '../services/chat_launcher.dart';
import '../services/report_repository.dart';
import '../services/session.dart';
import '../widgets/role_badge.dart';
import '../widgets/report_sheet.dart';
import 'auth/auth_wall_dialog.dart';
import 'applicants_screen.dart';

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

class _PostDetailScreenState extends State<PostDetailScreen>
    with SingleTickerProviderStateMixin {
  final _repo = CommunityRepository.instance;
  final _commentCtrl = TextEditingController();

  late Post _post;
  List<Comment> _comments = [];
  bool _loadingComments = true;
  bool _sending = false;
  bool _applying = false;
  bool _following = false;

  // 본문 최상단에서 아래로 당기면 화면이 축소되어 카드 자리로 돌아가는 제스처용.
  final _scroll = ScrollController();
  bool _dragging = false; // 축소 드래그 중(이 동안 본문 스크롤 잠금)
  bool _settling = false; // 손 뗌→축소 완주 중(추가 포인터 입력 무시, 곧 pop)
  Offset _dragStart = Offset.zero; // 포인터 시작점(이동량 계산)
  Offset _drag = Offset.zero; // 축소 UI 이동량(손가락 따라)

  bool get _collapsible => widget.originRect != null;

  // 축소 진행 로컬 컨트롤러(1=풀스크린, 0=카드). 라우트 컨트롤러와 분리 → 0 도달해도
  // 내비게이터 상태와 무관하므로 먹통이 발생하지 않는다.
  late final AnimationController _cc = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
    value: _collapsible ? 0 : 1,
  );

  // 드래그 중엔 스크롤 오프셋을 0으로 무력화(내용 고정). 물리 클래스는 그대로라
  // 스크롤 제스처가 취소되지 않아 포인터 취소→재진입 루프가 생기지 않는다.
  late final ScrollPhysics _physics = _LockableScrollPhysics(
    locked: () => _dragging,
    parent: const AlwaysScrollableScrollPhysics(
      parent: ClampingScrollPhysics(),
    ),
  );

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
    // 카드에서 열렸으면 카드(0)→풀스크린(1)으로 펼치며 등장.
    if (_collapsible) {
      _cc.animateTo(
        1,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
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
    _cc.dispose();
    _commentCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _atTop => !_scroll.hasClients || _scroll.position.pixels <= 0;

  void _onPointerDown(PointerDownEvent e) {
    if (_settling) return; // 축소 완주 중엔 새 입력 무시
    _dragStart = e.position;
  }

  /// 본문 최상단에서 아래로 끌면 축소 시작 → 이후 본문 스크롤을 잠그고(포인터 기준)
  /// 축소된 UI만 손가락 따라 움직인다. 로컬 컨트롤러(_cc)만 구동.
  void _onPointerMove(PointerMoveEvent e) {
    if (!mounted || _settling || !_collapsible) return;
    if (!_dragging) {
      final d = e.position - _dragStart;
      // 최상단에서 아래로(세로 우세) 끌기 시작할 때만 축소 모드 진입.
      if (_atTop && d.dy > 8 && d.dy > d.dx.abs()) {
        _dragStart = e.position; // 진입 지점 기준으로 이동량 재측정
        _dragging = true; // 스크롤 잠금(물리가 live 로 읽음, rebuild 불필요)
      }
      return;
    }
    final d = e.position - _dragStart;
    final vh = MediaQuery.of(context).size.height;
    final pull = d.dy.clamp(0.0, vh); // 아래로 당긴 양
    _drag = d; // 축소 UI를 손가락 따라 이동
    // 뷰포트 40% 당기면 카드 크기(_cc 0)까지 축소.
    _cc.value = 1 - (pull / (vh * 0.4)).clamp(0.0, 1.0);
  }

  void _onPointerUp([_]) {
    if (!mounted || _settling || !_dragging) return;
    _dragging = false;
    if (_cc.value < 0.97) {
      _startDismiss(); // 조금이라도 축소됐으면 그대로 닫힘(복귀 없음)
    } else {
      // 거의 안 움직였으면 원위치(축소로 볼 수 없는 미세 이동).
      _drag = Offset.zero;
      _cc.animateTo(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// 축소 완주(카드까지)를 시작. 뒤로가기·드래그 릴리스 공통 진입점.
  void _startDismiss() {
    if (_settling) return;
    setState(() => _settling = true); // PopScope.canPop 갱신 + 추가 입력 무시
    final dur = Duration(milliseconds: (260 + 300 * _cc.value).round());
    _cc.animateTo(0, duration: dur, curve: Curves.easeOutCubic).whenComplete(
      () {
        if (mounted) Navigator.of(context).pop();
      },
    );
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
    final color = categoryColor(_post.category);

    final scaffold = Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        actions: [
          if (!_isMyPost)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: '채팅하기',
              onPressed: _startChat,
            ),
          if (!_isMyPost)
            IconButton(
              icon: const Icon(Icons.report_outlined),
              tooltip: '신고',
              color: AppColors.danger,
              onPressed: _openPostMenu,
            ),
        ],
      ),
      body: SafeArea(
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: ListView(
            controller: _scroll,
            // 물리 클래스를 바꾸지 않고(포인터 취소 방지) 드래그 중엔 스크롤 오프셋만
            // 무력화 → 내용은 고정, 스크롤은 유효해 취소/재진입 무한루프가 없다.
            physics: _physics,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
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
              if (_post.imageUrl != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: kPostImageAspectRatio, // 4284 : 5712
                    child: Image.network(
                      _post.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: AppColors.surfaceMuted),
                    ),
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        post: _post,
        controller: _commentCtrl,
        sending: _sending,
        onHeart: _toggleHeart,
        onSend: _sendComment,
      ),
    );

    if (!_collapsible) return scaffold;
    // 카드에서 열렸으면 로컬 컨트롤러(_cc)로 카드↔풀스크린 변환을 화면 안에서 처리.
    final cardWidget = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: widget.originRect!.width,
        height: widget.originRect!.height,
        child: widget.cardBuilder!(context),
      ),
    );
    // 뒤로가기(버튼/스와이프)도 즉시 pop 대신 카드로 축소 완주 후 제거.
    return PopScope(
      canPop: _settling,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _startDismiss();
      },
      child: AnimatedBuilder(
        animation: _cc,
        builder: (context, child) => _wrapCollapse(context, child!, cardWidget),
        child: scaffold,
      ),
    );
  }

  /// 풀스크린 콘텐츠(child)를 _cc 값에 따라 카드 사각형으로 균일 축소·클립하고,
  /// 카드 크기에서 실제 카드로 크로스페이드한다(피드 카드와 완전히 동일).
  Widget _wrapCollapse(BuildContext context, Widget child, Widget cardWidget) {
    final origin = widget.originRect!;
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final p = _cc.value.clamp(0.0, 1.0); // 1=풀스크린, 0=카드
    final t = 1 - p; // 0=풀스크린, 1=축소

    // 보이는 창: 풀스크린(0,0,w,h) → 카드 사각형. t=1 이면 정확히 카드 크기·위치.
    // 드래그 이동량은 p 로 감쇠 → 카드 도착 시 슬롯에 정확히 안착.
    final win = Rect.lerp(Offset.zero & size, origin, t)!.shift(_drag * p);
    final scale = win.width / w; // 폭 기준 균일 축소(세로 동일 → 왜곡 없음)
    final radius = 20.0 * (t * 2).clamp(0.0, 1.0);
    final scrim = 0.32 * p; // 뒤 피드 딤(축소될수록 사라져 카드로 인계)
    final cardFade = ((t - 0.5) / 0.5).clamp(0.0, 1.0); // t 0.5→1: 상세→카드

    return Stack(
      fit: StackFit.expand,
      children: [
        if (scrim > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: scrim)),
            ),
          ),
        Positioned.fromRect(
          rect: win,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cardFade < 1)
                  Opacity(
                    opacity: 1 - cardFade,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: w,
                      maxWidth: w,
                      minHeight: h,
                      maxHeight: h,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topLeft,
                        filterQuality: FilterQuality.low,
                        child: child,
                      ),
                    ),
                  ),
                if (cardFade > 0)
                  Opacity(
                    opacity: cardFade,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Transform.scale(
                        scale: win.width / origin.width,
                        alignment: Alignment.topLeft,
                        filterQuality: FilterQuality.low,
                        child: cardWidget,
                      ),
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
    final initial = post.authorNickname.isEmpty
        ? '?'
        : post.authorNickname.characters.first;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primarySoft,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
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
              '${timeAgo(post.createdAt)} · 조회 ${post.viewCount}',
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
        final initial = c.authorNickname.isEmpty
            ? '?'
            : c.authorNickname.characters.first;
        final isMine = myUserId != null && c.userId == myUserId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: isMine ? null : () => onReport(c),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
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

/// 잠겼을 때 사용자 스크롤 오프셋을 0으로 무력화하는 스크롤 물리.
/// 물리 클래스 자체는 유지되므로(스크롤 가능 상태) 드래그가 취소되지 않아,
/// 축소 제스처 중에도 포인터 취소→재진입 루프 없이 내용만 고정된다.
class _LockableScrollPhysics extends ScrollPhysics {
  final ValueGetter<bool> locked;
  const _LockableScrollPhysics({required this.locked, super.parent});

  @override
  _LockableScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _LockableScrollPhysics(locked: locked, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      locked() ? 0.0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => locked() ? null : super.createBallisticSimulation(position, velocity);
}
