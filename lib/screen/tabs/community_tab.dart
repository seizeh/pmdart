import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../models/community.dart';
import '../../motion/motion.dart';
import '../../services/app_events.dart';
import '../../services/business/mode_repository.dart';
import '../../services/community/post_engagement_repository.dart';
import '../../services/community/post_query_repository.dart';
import '../../services/keyboard_barrier.dart';
import '../../services/notification_repository.dart';
import '../../services/profile_repository.dart';
import '../../theme/app_palette.dart';
import '../../utils/layout.dart';
import '../../widgets/app_invite_dialog.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/post_card.dart';
import '../../widgets/role_badge.dart';
import '../auth/auth_wall_dialog.dart';
import '../location_verify_screen.dart';
import '../notification_panel.dart';
import '../notifications_screen.dart';
import '../post_create_screen.dart';
import '../post_detail_screen.dart';

/// 커뮤니티 탭 — 게시글 목록(실데이터) + 카테고리 필터 + 검색.
class CommunityTab extends StatefulWidget {
  final bool isGuest;

  /// 아래로 스크롤 시 함께 숨길 상단/하단 크롬(하단 네비 바) 표시 여부.
  /// FAB 와 동일 신호로 토글된다.
  final ValueNotifier<bool>? chromeVisible;
  const CommunityTab({super.key, this.isGuest = false, this.chromeVisible});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab>
    with TickerProviderStateMixin {
  final _feedRepo = PostQueryRepository.instance;
  final _engage = PostEngagementRepository.instance;

  // 글쓰기 FAB 표시 스프링(1=보임, 0=숨김). 아래로 스크롤 시 숨고 위로 올리면 다시 팝.
  late final AnimationController _fabCtrl = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool _fabShown = true;

  // 카테고리 칩 표시 스프링(1=보임, 0=숨김).
  // 규칙: 최상단이거나 검색이 활성(포커스 또는 검색어 존재)일 때만 보인다.
  late final AnimationController _chipsCtrl = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool _chipsShown = true;
  final _searchFocus = FocusNode();

  // 스크롤 위치 조회용(상세 복귀 시 최상단 여부 판단).
  final _scrollCtrl = ScrollController();

  // 게시글 카드별 GlobalKey — 탭 시 카드의 화면 위치를 캡처해 상세를 그 자리에서
  // 펼치고, 아래로 당기면 그 자리로 축소시키는 CollapseRoute 에 넘긴다.
  final _cardKeys = <String, GlobalKey>{};

  // 지금 피드에서 **자리를 비운** 카드들 — 상세로 열려 있거나 패널로/패널에서
  // 날아가는 중이다. 자리(높이)는 그대로 두고 투명하게만 만든다: 축소 애니메이션이
  // 실제 카드와 겹치지 않고 빈 슬롯에 안착하며, 데스크톱에서는 그 **빈 슬롯 자체가
  // "지금 보고 있는 글" 표시이자 돌아올 자리**가 된다.
  //
  // 하나가 아니라 집합인 이유: 패널에서 글을 갈아탈 때 나가는 카드와 들어오는 카드가
  // **동시에** 날아 서로 엇갈린다.
  final _awayPostIds = <String>{};

  // 글쓰기 FAB 위치 캡처용 — 버튼에서 펼쳐지고 버튼으로 축소되는 전환에 사용.
  final _fabKey = GlobalKey();

  // ── 마스터-디테일(데스크톱 웹) — 우측 상세 패널 ─────────────────────────
  //
  // 패널은 **자기 Navigator** 를 갖는다. 상세를 위젯으로 직접 박지 않고 라우트로
  // 두는 이유: 뒤로가기·아래로 당겨 축소(PopScope)·상세 안에서의 추가 이동이
  // 전부 지금 코드 그대로 동작한다. 상세 화면은 한 줄도 고치지 않는다.
  final _panelNavKey = GlobalKey<NavigatorState>();

  // 패널 박스 — 라우트 좌표의 기준(RouteHost). 이걸 안 넘기면 카드에서 펼쳐지는
  // 모프가 본문 컬럼 기준으로 계산돼 피드 폭만큼 어긋난다.
  final _panelHostKey = GlobalKey();

  // 패널에 열려 있는 게시글 id — 없으면 빈 패널(안내). 카드가 나는 동안에도 이미
  // 그 글이 주인이다(도중에 다른 글을 누르면 이 값으로 주인이 바뀐 걸 알아챈다).
  String? _panelPostId;

  // 패널에 올려둔 상세 라우트 — 갈아탈 때 애니메이션 없이 걷어내려고 들고 있는다.
  Route<void>? _panelRoute;

  // 피드 subtree 를 창 크기 변화 너머로 **살려 두기** 위한 키.
  //
  // 1100 경계를 넘으면 피드가 Row 안팎으로 옮겨 다닌다. 키가 없으면 그때마다
  // 엘리먼트가 새로 만들어져 **스크롤 위치가 0 으로 튀고**, 헤더는 숨은 상태
  // 그대로라 목록 위에 빈 흰 띠가 남는다. GlobalKey 면 트리만 옮겨 붙는다.
  final _feedKey = GlobalKey();

  /// 지금 상세를 패널로 여는 배치인지 — 패널 Navigator 가 실제로 붙어 있을 때만.
  bool get _hasPanel => _panelNavKey.currentState != null;

  // 헤더 두 섹션 높이(오버레이+애니메이션): 제목+검색 / 카테고리 칩.
  // 패널이 상태바 아래로 8 떠 있으므로(플로팅 카드) 그만큼 더해 콘텐츠 높이를 유지.
  static const _searchSectionH = 124.0;
  static const _chipsSectionH = 52.0;
  static const _headerH = _searchSectionH + _chipsSectionH;

  // 크롬(FAB + 하단 네비 바) 표시 상태 변경을 한곳에서 처리.
  void _setChromeShown(bool show, {required SpringDescription spring}) {
    if (_fabShown == show) return;
    _fabShown = show;
    _fabCtrl.springTo(show ? 1 : 0, spring: spring);
    widget.chromeVisible?.value = show; // 하단 네비 바도 함께 숨김/복귀
  }

  bool _onUserScroll(UserScrollNotification n) {
    final dir = n.direction;
    // 헤더가 밀려날 만큼 스크롤되기 전(상단 근처)엔 항상 표시 → 헤더 숨김 시 빈 공간 방지.
    if (n.metrics.pixels < _headerH) {
      _setChromeShown(true, spring: MotionSprings.standard);
      return false;
    }
    if (dir == ScrollDirection.reverse) {
      _setChromeShown(false, spring: MotionSprings.standard);
    } else if (dir == ScrollDirection.forward) {
      _setChromeShown(true, spring: MotionSprings.bounce);
    }
    return false;
  }

  String? _selectedCategory; // null = 전체
  List<Post> _posts = [];
  bool _loading = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  /// 응답 순서 꼬임 방지 — 검색어·카테고리를 빠르게 바꾸면 앞선 요청이 **나중에**
  /// 도착해 새 목록을 옛 결과로 덮는다(사용자 검색의 같은 이름 필드와 동일 규칙).
  int _reqId = 0;

  static const _categories = [
    'news', // 업체 소식 — '전체' 칩 바로 다음
    'walk_together',
    'walk_proxy',
    'care',
    'give_away',
    'adoption',
    'free',
  ];

  // 카테고리 칩 행 위치 캡처 — 키보드 배리어 예외 영역 등록용.
  final _chipsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.instance.feed.addListener(_onFeedEvent);
    _searchFocus.addListener(_updateChipsVisible);
    _scrollCtrl.addListener(_updateChipsVisible);
    // 검색 키보드가 떠 있어도 카테고리 칩은 탭(선택)·가로 스크롤을 그대로
    // 받아야 하므로 배리어 예외 영역으로 등록한다.
    keyboardBarrierExemptAreas.add(_chipsExemptRect);
  }

  /// 칩 행의 현재 전역 rect — 커뮤니티 검색 포커스 중 + 칩이 보일 때만 유효.
  /// (다른 탭/화면의 키보드에서는 null → 예외 없음.)
  Rect? _chipsExemptRect() {
    if (!mounted || !_chipsShown || !_searchFocus.hasFocus) return null;
    final box = _chipsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 카테고리 칩 표시 갱신 — 최상단 || 검색 활성(포커스/검색어)일 때만.
  void _updateChipsVisible() {
    final atTop = !_scrollCtrl.hasClients || _scrollCtrl.offset <= 2;
    final searchActive = _searchFocus.hasFocus || _query.isNotEmpty;
    final show = atTop || searchActive;
    if (show == _chipsShown) return;
    _chipsShown = show;
    _chipsCtrl.springTo(
      show ? 1 : 0,
      spring: show ? MotionSprings.bounce : MotionSprings.standard,
    );
  }

  // 활동 범위 등 피드 영향 변경 시 즉시 재조회.
  void _onFeedEvent() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    keyboardBarrierExemptAreas.remove(_chipsExemptRect);
    AppEvents.instance.feed.removeListener(_onFeedEvent);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _fabCtrl.dispose();
    _chipsCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 검색어 변경 → 디바운스 후 재조회. silent — 키 입력마다 스피너로 리스트를
  /// 갈아엎지 않고 결과가 오면 바로 교체(타이핑 중 프레임 저하·깜빡임 방지).
  void _onSearchChanged(String v) {
    _query = v;
    _updateChipsVisible();
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _load(silent: true),
    );
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    _query = '';
    // 검색 취소 → 포커스도 내려 칩이 함께 사라지게(최상단이면 유지).
    _searchFocus.unfocus();
    _updateChipsVisible();
    // silent — 스피너 → 전체 리스트 순으로 두 번 갈아엎지 않고 기존 목록을 유지한 채
    // 데이터만 갱신(키보드 하강 애니메이션과 겹치며 프레임이 떨어지던 문제 완화).
    _load(silent: true);
  }

  /// [silent] 이면 로딩 스피너로 바꾸지 않고 목록을 유지한 채 데이터만 갱신한다.
  /// (상세에서 돌아올 때 리스트가 순간 축소→스크롤 최상단 점프하는 문제 방지.)
  Future<void> _load({bool silent = false}) async {
    final myReq = ++_reqId;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final posts = await _feedRepo.fetchFeed(
        category: _selectedCategory,
        query: _query,
      );
      if (!mounted || myReq != _reqId) return; // 더 최신 요청이 있으면 버린다
      setState(() {
        _posts = posts;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || myReq != _reqId) return;
      // 조용한 갱신 실패는 기존 목록을 유지한다(에러 화면으로 안 덮음).
      //
      // 단 **스피너가 떠 있으면 그냥 반환하면 안 된다.** 최초 로드가 비행 중일 때
      // 상세에서 돌아오며 silent 갱신이 _reqId 를 가져가면, 최초 로드의 응답은
      // 위 가드에서 버려진다 — 이 실패마저 조용히 반환하면 _loading 을 풀 사람이
      // 아무도 남지 않아 스피너가 영원히 돈다.
      if (silent && !_loading) return;
      setState(() {
        _error = '게시글을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  // 상세에서 돌아왔을 때 최상단이면 헤더(검색/카테고리)를 다시 펼친다.
  // (헤더가 숨은 채 최상단으로 돌아와 흰 공백이 보이던 문제 방지.)
  void _revealHeaderIfAtTop() {
    final atTop = !_scrollCtrl.hasClients || _scrollCtrl.offset < _headerH;
    if (atTop) _setChromeShown(true, spring: MotionSprings.standard);
  }

  // 카드의 현재 화면상 글로벌 사각형(축소 도착 지점). 못 찾으면 null.
  Rect? _cardRect(String id) {
    final box = _cardKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openPost(Post post) async {
    if (_hasPanel) return _openPostInPanel(post);
    final rect = _cardRect(post.id);
    // 카드 위치를 알면 그 자리에서 펼치고/당기면 축소되는 상세(투명 CollapseRoute),
    // 못 구하면 표준 라우트로 폴백. 축소 시 나타날 실제 카드는 피드와 동일 위젯.
    final page = PostDetailScreen(
      post: post,
      isGuest: widget.isGuest,
      originRect: rect,
      cardBuilder: rect == null ? null : (_) => PostCard(post: post),
    );
    // 카드 확장/축소 동안 원본 카드를 빈자리로(축소가 겹침 없이 안착).
    if (rect != null) setState(() => _awayPostIds.add(post.id));
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page)
          : CollapseRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    setState(() => _awayPostIds.remove(post.id)); // 상세 닫힘 → 원본 카드 복원
    _revealHeaderIfAtTop(); // 최상단이면 헤더 복귀(흰 공백 방지)
    unawaited(_load(silent: true)); // 스크롤 유지한 채 하트/댓글 변동만 반영
  }

  /// 상세 패널의 화면상 사각형. 아직 배치 전이면 null.
  Rect? _panelRect() {
    final box = _panelHostKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 날아간 카드가 패널 안에서 **착지하는 자리** — 카드 크기 그대로, 패널 중앙.
  /// 여기서부터는 상세가 사방으로 벌어진다(상세의 `contentAlignment` 가 center).
  Rect _landingRect(Rect card, Rect panel) => Rect.fromCenter(
    center: panel.center,
    width: card.width,
    height: card.height,
  );

  /// 상세를 우측 패널에 연다(데스크톱) — **카드가 목록을 떠나 패널로 날아간 뒤
  /// 그 자리에서 펼쳐진다.**
  ///
  /// 2단으로 나눈 이유: 이동 구간은 피드와 패널에 걸쳐 있어 어느 한쪽 박스 안에서
  /// 그리면 잘린다(자세한 사정은 [flyCard] 주석). 착지 뒤의 확장은 패널 안에서
  /// 끝나므로 기존 [CollapseRoute] 를 그대로 쓴다 — 아래로 당겨 축소도 공짜로 딸려온다.
  Future<void> _openPostInPanel(Post post) async {
    final nav = _panelNavKey.currentState;
    if (nav == null || _panelPostId == post.id) return;

    final cardRect = _cardRect(post.id);
    final panelRect = _panelRect();
    // 카드 위치를 못 구하면(스크롤로 화면 밖 등) 모션 없이 바로 띄운다.
    if (cardRect == null || panelRect == null) {
      setState(() => _panelPostId = post.id);
      unawaited(_runPanelRoute(post, null));
      return;
    }
    final landing = _landingRect(cardRect, panelRect);

    // 열려 있던 글은 **즉시** 카드로 되돌려 제 자리로 보낸다. 축소 애니메이션을
    // 태우면 나가는 카드가 착지점에 머무는 동안 들어오는 카드가 같은 자리에 도착해
    // 두 장이 겹친다. 이렇게 하면 둘이 서로 엇갈려 지나간다.
    final leaving = _panelRoute;
    if (leaving != null) nav.removeRoute(leaving);

    setState(() {
      _awayPostIds.add(post.id); // 목록에서 자리를 비운다(= 선택 표시)
      _panelPostId = post.id;
    });

    // 1단 — 목록에서 패널로 이동.
    await flyCard(
      context: context,
      from: toRouteRect(context, cardRect)!,
      to: toRouteRect(context, landing)!,
      card: (_) => PostCard(post: post),
    );
    // 나는 동안 다른 글로 갈아탔으면 여기서 멈춘다 — 그 글이 패널의 주인이다.
    if (!mounted || _panelPostId != post.id) return;

    // 2단 — 착지한 카드에서 상세로 확장.
    await _runPanelRoute(post, landing);
  }

  /// 패널에 상세 라우트를 올리고, 닫힐 때까지 기다렸다가 카드를 제 자리로 돌려보낸다.
  Future<void> _runPanelRoute(Post post, Rect? landing) async {
    final nav = _panelNavKey.currentState;
    if (nav == null) return;
    final route = landing == null
        ? AppPageRoute<void>(
            builder: (_) =>
                PostDetailScreen(post: post, isGuest: widget.isGuest),
          )
        : CollapseRoute<void>(
            builder: (_) => PostDetailScreen(
              post: post,
              isGuest: widget.isGuest,
              // 규약대로 화면 좌표 — 패널의 RouteHost 가 패널 좌표로 바꾼다.
              originRect: landing,
              cardBuilder: (_) => PostCard(post: post),
            ),
          );
    _panelRoute = route;
    nav.push(route);

    await route.popped;
    if (identical(_panelRoute, route)) _panelRoute = null;
    if (!mounted) return;
    // 축소가 끝나면 콘텐츠는 다시 착지점의 카드 모양이다 → 목록의 제 자리로.
    await _returnCardHome(post, landing);
    unawaited(_load(silent: true)); // 하트/댓글 변동만 반영(스크롤 유지)
  }

  /// 패널을 떠난 카드를 목록의 제 자리로 날려 보내고 슬롯을 복원한다.
  Future<void> _returnCardHome(Post post, Rect? landing) async {
    // 이미 다른 글이 패널을 차지했으면 그쪽 상태는 건드리지 않는다.
    if (_panelPostId == post.id) setState(() => _panelPostId = null);
    // 돌아갈 자리는 **지금** 다시 잰다 — 나 있는 동안 사용자가 스크롤했을 수 있다.
    final home = _cardRect(post.id);
    if (landing != null && home != null) {
      await flyCard(
        context: context,
        from: toRouteRect(context, landing)!,
        to: toRouteRect(context, home)!,
        card: (_) => PostCard(post: post),
      );
    }
    if (mounted) setState(() => _awayPostIds.remove(post.id));
  }

  void _selectCategory(String? c) {
    setState(() => _selectedCategory = c);
    _load();
  }

  Future<void> _toggleHeart(int index) async {
    if (widget.isGuest) {
      unawaited(AuthWallDialog.show(context, message: '하트는 로그인 후 누를 수 있어요'));
      return;
    }
    final post = _posts[index];
    final was = post.hearted;
    setState(
      () => _posts[index] = post.copyWith(
        hearted: !was,
        heartCount: post.heartCount + (was ? -1 : 1),
      ),
    );
    try {
      await _engage.toggleHeart(post.id, was);
    } catch (_) {
      if (!mounted) return;
      setState(() => _posts[index] = post); // 롤백
    }
  }

  // 글쓰기 FAB 의 현재 화면상 사각형(전환 원본). 못 찾으면 null.
  Rect? _fabRect() {
    final box = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openCreate() async {
    if (widget.isGuest) {
      unawaited(AuthWallDialog.show(context, message: '게시글은 로그인 후 작성할 수 있어요'));
      return;
    }
    // 동네 인증 게이트 — 미인증/만료(30일)면 작성 화면 대신 인증 안내.
    // (서버 create_post_verified 가 최종 차단하므로 여긴 UX 선안내.
    //  상태 조회가 실패하면 서버 게이트에 맡기고 통과시킨다.)
    // 업체 모드는 면제 — 소식(news) 글은 사업장 주소 기준이라 동네 인증 불필요.
    bool regionOk;
    try {
      final mode = await AccountModeRepository.instance.fetchActiveMode();
      regionOk =
          mode == 'business' ||
          await ProfileRepository.instance.isRegionVerificationFresh();
    } catch (_) {
      regionOk = true;
    }
    if (!mounted) return;
    if (!regionOk) {
      _showRegionGateDialog();
      return;
    }
    final rect = _fabRect();
    // 버튼에서 펼쳐지고, 아래로 쓸어내리면 버튼으로 축소되며 닫히는 전환 —
    // 작성 화면이 게시글 상세와 같은 전체화면 카드라 상세와 동일한 래퍼를 쓴다.
    // 버튼 위치를 못 구하면 하단에서 떠오르는 모달형 원점으로 대체.
    final created = await Navigator.push<bool>(
      context,
      CollapseRoute<bool>(
        builder: (_) => PostCreateScreen(
          originRect: rect ?? riseOriginRect(context),
          cardBuilder: rect == null ? null : (_) => const _FabGhost(),
          cardRadius: rect == null ? 0 : rect.height / 2,
        ),
      ),
    );
    if (created == true) unawaited(_load());
  }

  /// 동네 인증이 없거나 만료된 사용자에게 인증 화면으로 안내.
  /// 웹은 위치를 수집하지 않으므로(법·신뢰성) 앱으로 보낸다 — 현재 웹에서는
  /// 글쓰기 FAB 자체가 없어 여기까지 오지 않지만, 경로가 열려도 안전하게.
  void _showRegionGateDialog() {
    if (kIsWeb) {
      unawaited(AppInviteDialog.show(context, feature: '동네 인증'));
      return;
    }
    _showRegionGateDialogNative();
  }

  void _showRegionGateDialogNative() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('동네 인증이 필요해요'),
        content: const Text(
          '게시글은 동네 인증 후 작성할 수 있어요.\n'
          '현재 위치로 활동 지역을 인증해주세요. (30일마다 재인증)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.push(
                context,
                AppPageRoute(builder: (_) => const LocationVerifyScreen()),
              );
            },
            child: const Text('인증하러 가기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // 창이 넓고(useMasterDetail) **실제로 받은 폭도 충분할 때만** 쪼갠다.
        // 창 폭만 보면 안 된다 — 이 탭은 IndexedStack 안에 살아 있어서, 다른 탭을
        // 보는 동안에는 셸이 460 컬럼으로 되돌린 폭을 받는다. 그때 패널을 그리면
        // 넘친다.
        final split =
            useMasterDetail(context) &&
            c.maxWidth >=
                kContentMaxWidth + kDetailPanelGap + kDetailPanelMinWidth;
        final feed = KeyedSubtree(key: _feedKey, child: _feed());
        if (!split) {
          // 패널이 사라지면 그 안의 Navigator 도 함께 사라진다 — 열려 있던 라우트는
          // pop 되는 게 아니라 통째로 폐기되므로 `route.popped` 가 영영 완료되지
          // 않는다. 여기서 직접 지우지 않으면 id 가 남아, 창을 다시 넓힌 뒤 같은
          // 글을 눌러도 "이미 열려 있음"으로 무시된다.
          if (_panelPostId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _panelPostId != null && !_hasPanel) {
                setState(() {
                  _panelPostId = null;
                  _panelRoute = null;
                  // 자리를 비워 둔 카드도 되살린다 — 안 그러면 좁은 화면으로
                  // 내려온 목록에 투명한 빈 슬롯이 영구히 남는다.
                  _awayPostIds.clear();
                });
              }
            });
          }
          return feed;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 피드는 폰 폭 고정 — 카드 비율이 앱과 같아야 한다(결정 1).
            SizedBox(width: kContentMaxWidth, child: _sized(feed)),
            const SizedBox(width: kDetailPanelGap),
            Expanded(child: _detailPanel()),
          ],
        );
      },
    );
  }

  /// 자식에게 **자기가 실제로 차지한 크기**를 MediaQuery 로 알려준다.
  /// 안 하면 피드가 창(또는 피드+패널) 폭을 자기 크기로 착각한다.
  Widget _sized(Widget child) => LayoutBuilder(
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(size: Size(c.maxWidth, c.maxHeight)),
      child: child,
    ),
  );

  /// 우측 상세 패널 — 자기 Navigator 를 가진 작은 화면. 비어 있으면 안내를 띄운다.
  Widget _detailPanel() => SizedBox.expand(
    key: _panelHostKey, // 라우트 좌표의 기준(RouteHost 로 내려보낸다)
    child: _sized(
      RouteHost(
        hostKey: _panelHostKey,
        child: Navigator(
          key: _panelNavKey,
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const _EmptyDetailPanel(),
          ),
        ),
      ),
    ),
  );

  Widget _feed() {
    return Scaffold(
      backgroundColor: context.colors.background,
      // 키보드가 오르내릴 때 매 프레임 본문(블러 카드 리스트) 전체가 재레이아웃되며
      // 프레임이 떨어지므로 리사이즈를 끈다. 검색 UI 는 상단이라 가려질 것이 없고,
      // 결과 스크롤은 세로 스크롤 시작과 함께 키보드가 내려가 문제없다.
      resizeToAvoidBottomInset: false,
      body: Builder(
        builder: (context) {
          // paddingOf — viewInsets(키보드) 변화에는 리빌드되지 않도록 padding 만 구독.
          final topInset = MediaQuery.paddingOf(context).top;
          // 하단 바(높이 62 + 하단 안전영역) 뒤로 콘텐츠가 확장되므로 그만큼 하단 여백.
          // 좌측 레일(넓은 화면)에서는 가릴 것이 없어 0 이 된다.
          final bottomChrome = bottomNavClearance(context);
          return Stack(
            children: [
              // 게시글 스크롤 — 헤더 높이만큼 상단 패딩(헤더는 위에 오버레이).
              NotificationListener<UserScrollNotification>(
                onNotification: _onUserScroll,
                child: RefreshIndicator(
                  onRefresh: _load,
                  edgeOffset: topInset + _headerH,
                  child: CustomScrollView(
                    controller: _scrollCtrl,
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: topInset + _headerH + 4),
                      ),
                      _buildList(),
                      SliverToBoxAdapter(
                        child: SizedBox(height: bottomChrome + 24),
                      ),
                    ],
                  ),
                ),
              ),
              // 헤더 오버레이 — 스크롤 방향에 따라 하나의 스프링으로 위로 숨김/복귀
              // (FAB 와 같은 _fabCtrl → 완벽히 동기화). 파란/빨간 섹션은 별개 위젯.
              AnimatedBuilder(
                animation: _fabCtrl,
                builder: (context, child) {
                  final hidden = 1 - _fabCtrl.value.clamp(0.0, 1.0);
                  return Transform.translate(
                    offset: Offset(0, -hidden * (topInset + _headerH)),
                    child: child,
                  );
                },
                child: SizedBox(
                  height: topInset + _headerH,
                  child: Column(
                    children: [
                      // 파란 섹션: 상태바 + 제목 + 검색 (프로스트가 상태바까지 덮음)
                      SizedBox(
                        height: topInset + _searchSectionH,
                        child: _searchSection(topInset),
                      ),
                      // 빨간 섹션: 카테고리 칩 (완전 투명 → 게시글이 뒤로 비침).
                      // 평소엔 숨고, 최상단이거나 검색 활성일 때 제자리에서 스프링으로 등장.
                      SizedBox(
                        key: _chipsKey,
                        height: _chipsSectionH,
                        child: AnimatedBuilder(
                          animation: _chipsCtrl,
                          builder: (context, child) {
                            final v = _chipsCtrl.value.clamp(0.0, 1.0);
                            return IgnorePointer(
                              ignoring: v < 0.5,
                              child: Opacity(
                                opacity: v,
                                child: Transform.translate(
                                  offset: Offset(0, -10 * (1 - v)),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: _chipsSection(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      // 아래로 스크롤 시 스프링으로 아래로 사라지고, 위로 올리면 bounce 로 팝하며 복귀.
      // 웹은 글쓰기가 앱 전용이라 FAB 자체를 노출하지 않는다(docs/web-port.md) —
      // 동네 인증이 없어 서버(create_post_verified)가 어차피 막는다.
      floatingActionButton: kIsWeb
          ? null
          : AnimatedBuilder(
              animation: _fabCtrl,
              builder: (context, child) {
                final o = _fabCtrl.value.clamp(0.0, 1.0);
                // extendBody 로 화면 끝까지 확장되므로 하단 바(62)+안전영역만큼 띄워
                // FAB 가 바 뒤로 가려지지 않게 한다.
                return Padding(
                  padding: EdgeInsets.only(
                    // iOS 는 홈 인디케이터 인셋 체감상 하단 메뉴바와 너무 붙어 보여
                    // 조금 더 띄운다(Android 는 현행 간격 유지).
                    bottom:
                        (Theme.of(context).platform == TargetPlatform.iOS
                            ? 108.0
                            : 90.0) +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Opacity(
                    opacity: o,
                    child: Transform.translate(
                      offset: Offset(0, (1 - _fabCtrl.value) * 96),
                      child: IgnorePointer(ignoring: o < 0.5, child: child),
                    ),
                  ),
                );
              },
              child: FloatingActionButton.extended(
                key: _fabKey,
                onPressed: _openCreate,
                // 카테고리 칩(0.7)이 아닌 상단 필름과 동일한 투명도(0.92) 적용.
                backgroundColor: context.colors.primaryDark.withValues(
                  alpha: 0.92,
                ),
                foregroundColor: context.colors.textOnPrimary,
                elevation: 0,
                icon: const Icon(Icons.edit_outlined),
                label: const Text(
                  '글 쓰기',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
    );
  }

  // 파란 섹션: 제목 + 검색. 상태바 아래에 떠 있는 둥근 직사각형 패널(곡률 24,
  // 하단 메뉴바·다른 탭 헤더와 통일). 뒤 게시글이 흰색 셀로판지로 비친다.
  Widget _searchSection(double topInset) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: context.colors.frostFilm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
                child: Row(
                  children: [
                    Text(
                      '커뮤니티',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primaryDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    _NotificationBell(isGuest: widget.isGuest),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _SearchBar(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 빨간 섹션: 카테고리 칩. 배경 완전 투명 → 게시글이 뒤로 그대로 비친다.
  Widget _chipsSection() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 8),
      children: [
        _FilterChip(
          label: '전체',
          selected: _selectedCategory == null,
          onTap: () => _selectCategory(null),
        ),
        const SizedBox(width: 8),
        ..._categories.map(
          (c) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CategoryChip(
              category: c,
              selected: _selectedCategory == c,
              onTap: () => _selectCategory(_selectedCategory == c ? null : c),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return SliverToBoxAdapter(
        child: _MessageState(message: _error!, onRetry: _load),
      );
    }
    if (_posts.isEmpty) {
      return SliverToBoxAdapter(
        child: _MessageState(
          message: _query.trim().isNotEmpty
              ? '"${_query.trim()}" 검색 결과가 없어요'
              : '아직 게시글이 없어요.\n첫 게시글을 작성해보세요!',
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: _posts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final post = _posts[i];
          final key = _cardKeys.putIfAbsent(post.id, () => GlobalKey());
          return KeyedSubtree(
            key: key,
            // 상세로 열려있으면 투명(빈자리)으로 — 레이아웃/크기는 유지해 슬롯 그대로.
            child: Opacity(
              opacity: _awayPostIds.contains(post.id) ? 0.0 : 1.0,
              // RepaintBoundary 로 각 카드 리페인트를 격리(헤더 블러/애니메이션·이웃 카드
              // 하트 토글이 다른 카드를 다시 그리지 않게 함).
              child: RepaintBoundary(
                child: Entrance(
                  index: i,
                  child: PostCard(
                    post: post,
                    onTap: () => _openPost(post),
                    onHeart: () => _toggleHeart(i),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 아직 아무 글도 고르지 않았을 때의 우측 패널.
///
/// 빈 배경으로 두면 "레이아웃이 덜 만들어진 화면"으로 읽힌다. 무엇을 하면 되는지
/// 한 줄로 알려주는 것까지가 이 패널의 기본 상태다.
class _EmptyDetailPanel extends StatelessWidget {
  const _EmptyDetailPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 44,
            color: colors.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            '왼쪽에서 게시글을 고르면\n여기에서 바로 읽을 수 있어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 글쓰기 FAB 모양 복제 — 작성 화면 전환 시 버튼에서 펼쳐지고/버튼으로 축소될 때
/// 원본(버튼)으로 크로스페이드되는 위젯. 실제 FAB 와 색·아이콘·라벨을 맞춘다.
class _FabGhost extends StatelessWidget {
  const _FabGhost();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.primaryDark,
        borderRadius: BorderRadius.circular(100),
      ),
      // 실제 FloatingActionButton.extended 와 아이콘 크기(24)·라벨(14/w600)·간격(8)을 일치.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_outlined,
            color: context.colors.textOnPrimary,
            size: 24,
          ),
          SizedBox(width: 8),
          Text(
            '글 쓰기',
            style: TextStyle(
              color: context.colors.textOnPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _MessageState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              height: 1.5,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}

/// 알림 벨 — 실제 안읽음 수 배지 + 알림함 열기. 변경 시 자동 갱신.
class _NotificationBell extends StatefulWidget {
  final bool isGuest;
  const _NotificationBell({required this.isGuest});

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadCount();
      AppEvents.instance.notification.addListener(_loadCount);
    }
  }

  @override
  void dispose() {
    AppEvents.instance.notification.removeListener(_loadCount);
    super.dispose();
  }

  Future<void> _loadCount() async {
    try {
      final c = await NotificationRepository.instance.unreadCount();
      if (mounted) setState(() => _unread = c);
    } catch (e) {
      debugPrint('커뮤니티: 미읽음 수 조회 실패(기존 값 유지): $e');
    }
  }

  final _bellKey = GlobalKey();

  Future<void> _open() async {
    if (widget.isGuest) {
      unawaited(AuthWallDialog.show(context));
      return;
    }
    // 벨 위치를 앵커로 그 아래로 펼쳐지는 알림 패널을 연다(Slack 헤더-메뉴 스펠).
    // 목록을 먼저 받아 넘겨 첫 프레임부터 실제 크기로 확장되게 한다(로딩 중 크기 튐 방지).
    final box = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    if (anchor != null) {
      try {
        final items = await NotificationRepository.instance.fetch();
        if (!mounted) return;
        await showNotificationPanel(context, anchor, items);
        unawaited(_loadCount());
        return;
      } catch (_) {
        /* 실패 시 전체화면으로 폴백 */
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      AppPageRoute(builder: (_) => const NotificationsScreen()),
    );
    unawaited(_loadCount());
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _bellKey,
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          // 하단 내비와 같은 rounded 계열 — 뾰족한 모서리 없는 둥근 벨.
          Icon(
            Icons.notifications_rounded,
            color: context.colors.primaryDark,
            size: 26,
          ),
          if (!widget.isGuest && _unread > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: context.colors.danger,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  _unread > 99 ? '99+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBar({
    required this.controller,
    this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    // 공용 검색창(사용자 검색 디자인 기준)으로 위임.
    return AppSearchField(
      controller: controller,
      focusNode: focusNode,
      hintText: '게시글 검색...',
      onChanged: onChanged,
      onClear: onClear,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          // 채우기만 투명(테두리·글씨는 불투명 유지). CategoryChip 과 동일 값으로 통일.
          color: selected
              ? context.colors.primaryDark.withValues(alpha: 0.7)
              // 미선택 채우기 — 표면 토큰(라이트: 흰 필름 그대로, 다크: 어두운 필름).
              : context.colors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? context.colors.primaryDark
                : context.colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? context.colors.textOnPrimary
                : context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
