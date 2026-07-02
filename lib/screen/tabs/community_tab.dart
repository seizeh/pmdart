import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../../theme/app_colors.dart';
import '../../models/community.dart';
import '../../services/community_repository.dart';
import '../../widgets/post_card.dart';
import '../../widgets/role_badge.dart';
import '../../motion/motion.dart';
import '../../services/app_events.dart';
import '../../services/notification_repository.dart';
import '../auth/auth_wall_dialog.dart';
import '../post_detail_screen.dart';
import '../post_create_screen.dart';
import '../notifications_screen.dart';

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
    with SingleTickerProviderStateMixin {
  final _repo = CommunityRepository.instance;

  // 글쓰기 FAB 표시 스프링(1=보임, 0=숨김). 아래로 스크롤 시 숨고 위로 올리면 다시 팝.
  late final AnimationController _fabCtrl = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool _fabShown = true;

  // 스크롤 위치 조회용(상세 복귀 시 최상단 여부 판단).
  final _scrollCtrl = ScrollController();

  // 게시글 카드별 GlobalKey — 탭 시 카드의 화면 위치를 캡처해 상세를 그 자리에서
  // 펼치고, 아래로 당기면 그 자리로 축소시키는 CollapseRoute 에 넘긴다.
  final _cardKeys = <String, GlobalKey>{};

  // 글쓰기 FAB 위치 캡처용 — 버튼에서 펼쳐지고 버튼으로 축소되는 전환에 사용.
  final _fabKey = GlobalKey();

  // 헤더 그라데이션 블러 슬라이스 수(많을수록 띠 경계가 부드러움).
  static const _headerBlurSlices = 20;

  // 헤더 두 섹션 높이(오버레이+애니메이션): 파란(제목+검색) / 빨간(카테고리 칩).
  static const _searchSectionH = 116.0;
  static const _chipsSectionH = 52.0;
  static const _headerH = _searchSectionH + _chipsSectionH;

  // 프로스트 영역 내 i번째 띠의 블러 sigma: 상단 12 → 하단 0 (선형).
  double _sliceSigma(int i) => 12.0 * (1 - i / (_headerBlurSlices - 1));

  // 슬라이스 1개: sigma 가 충분히 작으면 블러 생략(0 블러/불필요 레이어 방지).
  Widget _sliceBlur(double sigma) {
    if (sigma < 0.5) return const SizedBox.expand();
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: const SizedBox.expand(),
    );
  }

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

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.instance.feed.addListener(_onFeedEvent);
  }

  // 활동 범위 등 피드 영향 변경 시 즉시 재조회.
  void _onFeedEvent() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    AppEvents.instance.feed.removeListener(_onFeedEvent);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _fabCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 검색어 변경 → 디바운스 후 재조회.
  void _onSearchChanged(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    _query = '';
    _load();
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
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page)
          : CollapseRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
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
      backgroundColor: Colors.white,
      body: Builder(
        builder: (context) {
          final topInset = MediaQuery.of(context).padding.top;
          // 하단 바(높이 62 + 하단 안전영역) 뒤로 콘텐츠가 확장되므로 그만큼 하단 여백.
          final bottomInset = MediaQuery.of(context).padding.bottom;
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
                      // 빨간 섹션: 카테고리 칩 (완전 투명 → 게시글이 뒤로 비침)
                      SizedBox(height: _chipsSectionH, child: _chipsSection()),
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
              bottom: 90 + MediaQuery.of(context).padding.bottom,
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
          backgroundColor: AppColors.primaryDark,
          foregroundColor: AppColors.textOnPrimary,
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

  // 파란 섹션: (상태바 +) 제목 + 검색. 뒤 게시글이 그라데이션 프로스트(블러+틴트)로 비친다.
  Widget _searchSection(double topInset) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          // 하단 경계선 양끝을 검색창과 같은 곡률로 둥글게(프로스트가 카드처럼 떨어짐).
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(32),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  for (int i = 0; i < _headerBlurSlices; i++)
                    Expanded(child: _sliceBlur(_sliceSigma(i))),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 3.2),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
                child: Row(
                  children: [
                    const Text(
                      '커뮤니티',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
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
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
              ),
            ],
          ),
        ),
      ],
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
            child: Entrance(
              index: i,
              child: PostCard(
                post: post,
                onTap: () => _openPost(post),
                onHeart: () => _toggleHeart(i),
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
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(100),
      ),
      // 실제 FloatingActionButton.extended 와 아이콘 크기(24)·라벨(14/w600)·간격(8)을 일치.
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_outlined, color: AppColors.textOnPrimary, size: 24),
          SizedBox(width: 8),
          Text(
            '글 쓰기',
            style: TextStyle(
              color: AppColors.textOnPrimary,
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
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
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

  Future<void> _open() async {
    if (widget.isGuest) {
      AuthWallDialog.show(context);
      return;
    }
    await Navigator.push(
      context,
      AppPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_outlined,
            color: AppColors.primaryDark,
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
                  color: AppColors.danger,
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
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.textTertiary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '게시글 검색...',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: onClear,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.close,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
          ),
        ],
      ),
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
          color: selected ? AppColors.primaryDark : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? AppColors.primaryDark : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
