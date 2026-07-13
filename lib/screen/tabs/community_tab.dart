import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../../theme/app_palette.dart';
import '../../models/community.dart';
import '../../services/community_repository.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/post_card.dart';
import '../../widgets/role_badge.dart';
import '../../motion/motion.dart';
import '../../services/app_events.dart';
import '../../services/keyboard_barrier.dart';
import '../../services/notification_repository.dart';
import '../auth/auth_wall_dialog.dart';
import '../post_detail_screen.dart';
import '../post_create_screen.dart';
import '../notifications_screen.dart';
import '../notification_panel.dart';

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
  final _repo = CommunityRepository.instance;

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

  // 상세보기로 열려있는 카드 id — 그 카드는 상세가 열린 동안 투명(빈자리)으로 두어,
  // 축소 애니메이션이 실제 카드와 겹치지 않고 빈 슬롯으로 깔끔히 안착하게 한다.
  String? _openedPostId;

  // 글쓰기 FAB 위치 캡처용 — 버튼에서 펼쳐지고 버튼으로 축소되는 전환에 사용.
  final _fabKey = GlobalKey();

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

  static const _categories = [
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
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final posts = await _repo.fetchFeed(
        category: _selectedCategory,
        query: _query,
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      if (silent) return; // 조용한 갱신 실패는 기존 목록 유지(에러 화면으로 안 덮음)
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
    if (rect != null) setState(() => _openedPostId = post.id);
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page)
          : CollapseRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    setState(() => _openedPostId = null); // 상세 닫힘 → 원본 카드 복원
    _revealHeaderIfAtTop(); // 최상단이면 헤더 복귀(흰 공백 방지)
    _load(silent: true); // 스크롤 유지한 채 하트/댓글 변동만 반영
  }

  void _selectCategory(String? c) {
    setState(() => _selectedCategory = c);
    _load();
  }

  Future<void> _toggleHeart(int index) async {
    if (widget.isGuest) {
      AuthWallDialog.show(context, message: '하트는 로그인 후 누를 수 있어요');
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
      await _repo.toggleHeart(post.id, was);
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
      AuthWallDialog.show(context, message: '게시글은 로그인 후 작성할 수 있어요');
      return;
    }
    final rect = _fabRect();
    // 버튼에서 펼쳐지고 버튼으로 축소되는 전환(상세 화면과 같은 맥락). 못 구하면 표준 전환.
    final created = await Navigator.push<bool>(
      context,
      rect == null
          ? AppPageRoute(builder: (_) => const PostCreateScreen())
          : ExpandRoute<bool>(
              originRect: rect,
              builder: (_) => const PostCreateScreen(),
              origin: (_) => const _FabGhost(),
            ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
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
          final bottomInset = MediaQuery.paddingOf(context).bottom;
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
                        child: SizedBox(height: 62 + bottomInset + 24),
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
      floatingActionButton: AnimatedBuilder(
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
          backgroundColor: context.colors.primaryDark.withValues(alpha: 0.92),
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
              opacity: post.id == _openedPostId ? 0.0 : 1.0,
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
    } catch (_) {}
  }

  final _bellKey = GlobalKey();

  Future<void> _open() async {
    if (widget.isGuest) {
      AuthWallDialog.show(context);
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
        _loadCount();
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
    _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _bellKey,
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.notifications_outlined,
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
              : Colors.white.withValues(alpha: 0.7),
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
