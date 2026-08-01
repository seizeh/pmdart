import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/community.dart';
import '../motion/motion.dart';
import '../services/business_repository.dart';
import '../services/chat_launcher.dart';
import '../services/community_repository.dart';
import '../services/report_repository.dart';
import '../services/session.dart';
import '../state/post_detail_state.dart';
import '../theme/app_palette.dart';
import '../utils/labels.dart' show timeAgo;
import '../utils/share_links.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/overlay_icon_button.dart';
import '../widgets/post_media_hero.dart';
import '../widgets/report_sheet.dart';
import 'applicants_screen.dart';
import 'auth/auth_wall_dialog.dart';
import 'post_edit_screen.dart';
import 'user_profile_screen.dart';

/// 신고 액션 시트의 한 항목.
class _ReportAction {
  final String label;
  final VoidCallback onTap;

  /// 차단은 신고와 성격이 달라(즉시 효력·되돌릴 수 있음) 아이콘으로 구분한다.
  final bool isBlock;
  const _ReportAction(this.label, this.onTap, {this.isBlock = false});
}

/// 게시글 상세 — 전 카테고리 쇼츠형: 전체화면 미디어(영상/사진/블롭) 위에
/// 피드 카드와 동일한 정보 오버레이(+ 매칭 글 지원 버튼), 댓글은 바텀시트.
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
  // 상태·서버 호출은 홀더가 갖고, 화면은 구독해 그리기 + 가드/다이얼로그/토스트/
  // 내비게이션만 담당한다 (docs/architecture-state.md).
  late final PostDetailState _state = PostDetailState(
    post: widget.post,
    isGuest: widget.isGuest,
  );
  final _commentCtrl = TextEditingController();

  // 본문 최상단에서 아래로 당기면 카드로 축소되는 CollapsibleView 용 스크롤 컨트롤러.
  final _scroll = ScrollController();

  // 영상 글의 쇼츠형 히어로가 재생하는 컨트롤러 — 화면이 소유한다.
  VideoPlayerController? _video;
  bool _videoError = false;

  /// 원본 보기(오버레이 숨김 + 미디어를 원본 비율로) — 히어로의 사진 탭과
  /// 앱바 좌측 아이콘이 공유하는 상태. 켜지면 앱바 우측 아이콘·오버레이가 숨고
  /// 당겨서 축소되는 드래그와 리스트 스크롤이 잠긴다(확대/이동과 충돌 방지).
  final _originView = ValueNotifier<bool>(false);
  bool get _overlayHidden => _originView.value;

  @override
  void initState() {
    super.initState();
    // 원본 보기 토글은 히어로(사진 탭)와 앱바 아이콘이 함께 쓴다 — 앱바·드래그
    // 잠금이 같이 반응하도록 화면도 구독한다.
    _originView.addListener(() {
      if (mounted) setState(() {});
    });
    // 카드에서 확장 진입하면 초기 로드(댓글·조회수·권한 등)를 전환이 안착한
    // 뒤로 미룬다 — 로드 알림(notifyListeners)마다 화면 전체가 리빌드되며
    // 확장 모프 프레임을 흔들던 문제(전환이 2단계로 끊겨 보임). 게시글 본문은
    // widget.post 로 이미 완전하므로 첫 프레임 표시에는 영향 없다.
    if (widget.originRect == null) {
      _state.init();
    } else {
      Future.delayed(const Duration(milliseconds: 480), () {
        if (mounted) _state.init();
      });
    }
    final post = widget.post;
    if (post.isVideo && post.imageUrl != null) {
      final video = VideoPlayerController.networkUrl(Uri.parse(post.imageUrl!));
      _video = video;
      // 끝나면 바로 이어서 반복 재생(쇼츠 문법).
      video.setLooping(true);
      video
          .initialize()
          .then((_) {
            if (!mounted) return;
            setState(() {});
            video.play();
          })
          .catchError((Object e) {
            if (mounted) setState(() => _videoError = true);
          });
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scroll.dispose();
    _video?.dispose();
    _originView.dispose();
    _state.dispose();
    super.dispose();
  }

  /// 원본 보기를 붙일 수 있는 미디어인가 — 사진은 언제나(탭·아이콘 모두),
  /// 영상은 화면을 채우느라 잘리는 세로·정방형만(가로 영상은 이미 전체가
  /// 보이고, 웹은 플랫폼 뷰라 애초에 자르지 않는다).
  bool get _canOriginView {
    final post = _state.post;
    if (post.imageUrl == null) return false; // 블롭 글
    if (!post.isVideo) return true;
    if (kIsWeb) return false;
    final v = _video?.value;
    return v != null && v.isInitialized && v.aspectRatio <= 1;
  }

  bool _guard(String message) {
    if (widget.isGuest) {
      AuthWallDialog.show(context, message: message);
      return false;
    }
    return true;
  }

  void _startChat() {
    if (!_guard('채팅은 로그인 후 이용할 수 있어요')) return;
    openDirectChat(context, _state.post.userId);
  }

  Future<void> _toggleHeart() async {
    if (!_guard('하트는 로그인 후 누를 수 있어요')) return;
    final ok = await _state.toggleHeart();
    if (!ok) _toast('잠시 후 다시 시도해주세요');
  }

  Future<void> _sendComment() async {
    if (!_guard('댓글은 로그인 후 작성할 수 있어요')) return;
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    if (await _state.submitComment(text)) {
      _commentCtrl.clear();
      // 시트 안에서 보낼 때도 키보드가 내려가도록 전역 포커스 해제.
      FocusManager.instance.primaryFocus?.unfocus();
      await _state.loadComments();
    } else {
      _toast('댓글 작성에 실패했어요');
    }
  }

  /// 댓글 바텀시트(전 카테고리) — 기존 댓글 리스트 + 입력창을 시트로.
  /// 열람은 게스트도 가능(작성은 [_sendComment] 의 가드가 막는다).
  void _openComments() {
    // 공용 셸 — 배리어 off·포커스 중 드래그 잠금은 showCommentsSheet/셸이 처리.
    showCommentsSheet<void>(
      context,
      builder: (_) => CommentsSheetShell(
        listenable: _state,
        title: () => '댓글 ${_state.comments.length}',
        inputController: _commentCtrl,
        sending: () => _state.sending,
        onSend: _sendComment,
        listBuilder: (_) => _CommentList(
          loading: _state.loadingComments,
          comments: _state.comments,
          myUserId: SessionManager.instance.user?.id,
          onReport: _openCommentMenu,
        ),
      ),
    );
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
    if (await _state.submitApply()) {
      _toast('지원했어요');
    } else {
      _toast('이미 지원했거나 지원할 수 없는 게시글이에요');
    }
  }

  void _openApplicants() {
    Navigator.push(
      context,
      AppPageRoute(builder: (_) => ApplicantsScreen(post: _state.post)),
    );
  }

  /// 오버레이 닉네임 탭 → 작성자 프로필. 직전 화면이 이 작성자의 프로필이면
  /// 새로 쌓지 않고 되돌아간다(프로필→게시글→작성자… 무한 스택 방지).
  void _openAuthor() {
    final post = _state.post;
    if (post.userId.isEmpty) return;
    if (widget.fromUserId != null && widget.fromUserId == post.userId) {
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.push(
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
          // (업체 글은 상호로 표시되고 업체 얼굴로 연다, 0025).
          forcePersonalFace: post.authoredAs != 'business',
        ),
      ),
    );
  }

  /// 매칭 카테고리(산책·돌봄·나눔) 전용 — 오버레이의 본문/약속 필과 하단 스탯
  /// 행 사이에 들어갈 지원 액션(카드에는 없음, 상세 전용). 자유·소식 글이나
  /// 노출 조건 미충족이면 null. 기존 노출 조건 유지:
  /// 내 글(관리자) → 지원자 보기, 모집 중 + 남의 글 → 지원하기(업체 모드 안내).
  Widget? _applySection() {
    final post = _state.post;
    if (_state.isFreePost) return null;
    if (_state.canManage) {
      return _OverlayActionButton(
        icon: Icons.people_outline,
        label: '지원자 목록 보기',
        onTap: _openApplicants,
      );
    }
    if (!_state.managerChecked || post.progressStatus != 'recruiting') {
      return null;
    }
    if (_state.businessMode) {
      // 업체 모드에선 지원(개인 매칭) 불가 — 버튼 대신 안내.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0x59000000),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '업체 모드에서는 지원할 수 없어요.\n산책·돌봄 매칭은 일반 모드에서 이용해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white70),
        ),
      );
    }
    return _OverlayActionButton(
      icon: Icons.send_outlined,
      label: '이 게시글에 지원하기',
      busy: _state.applying,
      onTap: _state.applying ? null : _apply,
    );
  }

  /// 내 게시글 수정 → 저장되면 최신 내용으로 다시 불러온다.
  Future<void> _openEdit() async {
    final saved = await Navigator.push<bool>(
      context,
      AppPageRoute(builder: (_) => PostEditScreen(post: _state.post)),
    );
    if (saved == true) {
      final alive = await _state.reloadPost();
      if (!mounted) return;
      if (!alive) {
        // 수정 화면에서 삭제됨 → 상세도 닫는다(축소 전환 경유).
        Navigator.of(context).maybePop();
      }
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 공유 — 뷰어 링크(go.pawmate.kr, 로그인 없이 열람) 발급 후 시스템 공유 시트.
  /// 링크는 게시글당 재사용·30일 유효(서버), 전 카테고리 공통.
  bool _sharing = false;
  Future<void> _sharePost() async {
    if (!_guard('공유는 로그인 후 할 수 있어요')) return;
    if (_sharing) return;
    _sharing = true;
    try {
      final token = await CommunityRepository.instance.createPostShareLink(
        _state.post.id,
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(text: '${_state.post.title}\n${shareViewUrl(token)}'),
      );
    } catch (_) {
      _toast('공유 링크를 만들지 못했어요. 잠시 후 다시 시도해주세요');
    } finally {
      _sharing = false;
    }
  }

  /// 게시글 상단 메뉴 — 게시글/작성자 신고(본인 글은 메뉴 미노출).
  void _openPostMenu() {
    if (!_guard('신고는 로그인 후 할 수 있어요')) return;
    final post = _state.post;
    _showReportActions([
      _ReportAction(
        '게시글 신고',
        () => _report(
          ReportRepository.targetPost,
          post.id,
          '게시글',
          post.title,
          authorId: post.userId,
        ),
      ),
      _ReportAction(
        '작성자 신고',
        () => _report(
          ReportRepository.targetUser,
          post.userId,
          '작성자',
          post.authorNickname,
        ),
      ),
      _ReportAction(
        '이 사용자 차단',
        () => _block(post.userId, post.authorNickname),
        isBlock: true,
      ),
    ]);
  }

  /// 댓글 길게 누르기 — 댓글/작성자 신고(본인 댓글은 호출 안 됨).
  void _openCommentMenu(Comment c) {
    if (!_guard('신고는 로그인 후 할 수 있어요')) return;
    _showReportActions([
      _ReportAction(
        '댓글 신고',
        () => _report(
          ReportRepository.targetComment,
          c.id,
          '댓글',
          c.content,
          authorId: c.userId,
        ),
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
                  a.isBlock ? Icons.block_outlined : Icons.flag_outlined,
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
    String title, {
    // 게시글·댓글은 targetId 가 콘텐츠라 작성자를 따로 넘겨야 '차단도 함께'가 뜬다.
    String? authorId,
  }) async {
    final ok = await showReportSheet(
      context,
      targetType: type,
      targetId: id,
      targetLabel: label,
      targetTitle: title,
      authorId: authorId,
    );
    if (ok && mounted) _toast('신고가 접수되었어요. 검토 후 조치할게요');
  }

  /// 사용자 차단 — 확인 후 즉시 적용하고 **이 화면을 벗어난다**.
  ///
  /// 차단한 사람의 글을 계속 보고 있으면 "차단했는데 그대로네"가 된다(App Store
  /// 1.2 의 '즉시 제거' 요건). 목록 쪽은 서버 뷰가 이미 걸러내므로 돌아가서
  /// 새로 받으면 사라져 있다.
  Future<void> _block(String userId, String nickname) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('이 사용자 차단'),
        content: Text(
          '$nickname 님을 차단할까요?\n\n'
          '· 이 사용자의 게시글이 목록에서 바로 사라져요\n'
          '· 신고도 함께 접수되어 검토해요\n'
          '· 차단은 내정보 > 차단 사용자 관리에서 해제할 수 있어요',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('차단'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ReportRepository.instance.block(userId);
      if (!mounted) return;
      _toast('$nickname 님을 차단했어요');
      Navigator.of(context).maybePop(); // 차단한 사람의 글에 머물지 않는다
    } catch (e) {
      if (mounted) _toast('차단하지 못했어요. 잠시 후 다시 시도해주세요');
      debugPrint('block failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
        // 카드에서 네 변이 동시에 벌어지는 사방 확장 — 히어로의 카드 미러
        // (세로 중앙 3:4 박스)와 짝.
        contentAlignment: Alignment.center,
        scrollController: _scroll,
        // 사진 원본 보기(오버레이 숨김) 중에는 당겨서 카드로 축소되는 드래그를
        // 잠근다 — 확대/이동 제스처가 그대로 커뮤니티 복귀로 읽히지 않도록.
        // 그 밖에는 기존과 동일(본문이 뷰포트 1장이라 늘 최상단).
        dragHandleTest: (_) => !_overlayHidden,
        builder: (context, physics) => ListenableBuilder(
          listenable: _state,
          builder: (context, _) {
            final post = _state.post;
            return Scaffold(
              // 투명(전 게시글 공통) — 축소 전환 중 카드(3:4) 아래로 뒤 피드가
              // 비치게(CollapseRoute opaque:false). 풀스크린에선 히어로가
              // 화면을 다 덮는다.
              backgroundColor: Colors.transparent,
              // 히어로(사진 또는 블롭 본문)가 상태바까지 차오르도록 앱바를 투명 오버레이로.
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                // 뒤로가기 버튼 없음 — 아래로 당겨 카드로 축소하거나 시스템 뒤로가기
                // (프로필·펫 상세와 동일한 몰입형).
                automaticallyImplyLeading: false,
                // 원본 보기 — 화면을 채우느라 잘린 미디어를 원본 비율로 본다.
                // 사진은 화면 탭으로도 되지만 영상은 탭이 재생/일시정지라 이
                // 아이콘이 유일한 입구다. 그래서 영상은 원본 보기 중에도 계속
                // 보이게 두고(돌아올 길), 사진은 몰입을 위해 함께 숨긴다.
                leading: _canOriginView
                    ? CollapseSettledFade(
                        visible: !_overlayHidden || _video != null,
                        child: OverlayIconButton(
                          icon: _overlayHidden
                              ? Icons.fullscreen
                              : Icons.aspect_ratio,
                          tooltip: _overlayHidden ? '화면 채우기' : '원본 보기',
                          onPressed: () =>
                              _originView.value = !_originView.value,
                        ),
                      )
                    : null,
                leadingWidth: 56,
                actions: [
                  // 앱바 아이콘은 확장 전환이 안착한 뒤에 페이드 인 — 카드
                  // 크로스페이드 중간에 불쑥 나타나 모프가 2단계로 끊겨
                  // 보이던 문제 해결(후기 상세와 같은 원샷 모프).
                  // 오버레이 몰입 토글(사진 탭) 시엔 함께 숨는다.
                  CollapseSettledFade(
                    visible: !_overlayHidden,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 공유 — 전 카테고리 공통(내 글·남 글 모두).
                        OverlayIconButton(
                          icon: Icons.ios_share,
                          tooltip: '공유',
                          onPressed: _sharePost,
                        ),
                        if (_state.isMyPost)
                          OverlayIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: '수정',
                            onPressed: _openEdit,
                          ),
                        if (!_state.isMyPost)
                          OverlayIconButton(
                            icon: Icons.chat_bubble_outline,
                            tooltip: '채팅하기',
                            onPressed: _startChat,
                          ),
                        if (!_state.isMyPost)
                          OverlayIconButton(
                            icon: Icons.report_outlined,
                            tooltip: '신고',
                            color: const Color(0xFFFF8A80),
                            onPressed: _openPostMenu,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              // 전 카테고리 쇼츠형 — 화면 = 전체화면 미디어(영상/사진/블롭)
              // 하나. 스크롤 본문 없이 뷰포트 높이 1장짜리 리스트로
              // CollapsibleView 의 당겨서 카드로 축소하는 드래그 메커니즘만
              // 보존한다. 댓글은 바텀시트, 하트·지원은 오버레이에서.
              body: ListView(
                controller: _scroll,
                // 원본 보기 중엔 리스트가 세로 드래그를 가져가지 않게 잠근다 —
                // 스크롤 인식기(슬롭 18)가 확대 이동(슬롭 36)보다 먼저 이겨
                // 사진을 위아래로 못 옮기던 문제. 그 밖에는 기존과 동일.
                physics: _overlayHidden
                    ? const NeverScrollableScrollPhysics()
                    : physics, // 드래그 중 잠금은 CollapsibleView 가 제공
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height,
                    child: PostMediaHero(
                      post: post,
                      controller: _video,
                      videoError: _videoError,
                      onHeart: _toggleHeart,
                      onComments: _openComments,
                      onAuthorTap: _openAuthor,
                      overlayExtra: _applySection(),
                      originView: _originView,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
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

/// 오버레이 위 지원 액션 버튼 — 어두운 스크림/미디어 위에서도 읽히는 밝은
/// 필름 알약(카테고리 태그와 같은 문법). 상세 전용(카드에는 없음).
class _OverlayActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  const _OverlayActionButton({
    required this.icon,
    required this.label,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = context.colors.primaryDark;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 17, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
