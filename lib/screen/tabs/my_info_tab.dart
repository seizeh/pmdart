import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../../motion/motion.dart';
import '../../theme/app_palette.dart';
import '../../data/mock_data.dart' show MockPet;
import '../../models/community.dart';
import '../../models/profile.dart';
import '../../services/profile_repository.dart';
import '../../services/pet_repository.dart';
import '../../services/business_repository.dart';
import '../../services/community_repository.dart';
import '../../services/app_events.dart';
import '../../services/session.dart';
import '../../widgets/pet_card.dart';
import '../../widgets/review_cards.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/gradient_header.dart';
import '../../widgets/overlay_icon_button.dart';
import '../activity_screens.dart' show MyAppointmentsScreen;
import '../connections_screen.dart';
import '../pet_detail_screen.dart';
import '../pet_edit_screen.dart';
import '../post_detail_screen.dart';
import '../profile_edit_screen.dart';
import '../user_profile_screen.dart' show PostPhotoTile;
import '../auth/login_screen.dart';
import '../auth/signup_phone_screen.dart';
import '../terms_screen.dart';

/// 화면 이동 공용 헬퍼.
void _push(BuildContext context, Widget screen) {
  Navigator.push(context, AppPageRoute(builder: (_) => screen));
}

/// 내정보 탭 — 내 반려동물(N:M) / 프로필 히어로 / 내 게시글(2열 그리드).
/// 내 활동·활동 범위·관심·설정은 프로필 히어로 탭 → 내정보 수정 화면에 있다.
class MyInfoTab extends StatefulWidget {
  final bool isGuest;

  /// 아래로 스크롤 시 함께 숨길 하단 크롬(네비 바) 표시 여부 — 커뮤니티와 동일 신호.
  final ValueNotifier<bool>? chromeVisible;
  const MyInfoTab({super.key, this.isGuest = false, this.chromeVisible});

  @override
  State<MyInfoTab> createState() => _MyInfoTabState();
}

class _MyInfoTabState extends State<MyInfoTab>
    with SingleTickerProviderStateMixin {
  // 상단 헤더(+하단 네비 바) 표시 스프링(1=보임, 0=숨김) — 커뮤니티와 동일 규칙:
  // 아래로 스크롤하면 숨고, 위로 올리면 스프링으로 복귀.
  late final AnimationController _chromeCtrl = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool _chromeShown = true;

  void _setChromeShown(bool show, {required SpringDescription spring}) {
    if (_chromeShown == show) return;
    _chromeShown = show;
    _chromeCtrl.springTo(show ? 1 : 0, spring: spring);
    widget.chromeVisible?.value = show; // 하단 네비 바도 함께 숨김/복귀
  }

  bool _onUserScroll(UserScrollNotification n) {
    // 펫 캐러셀(가로 PageView)의 스크롤은 무시 — 세로 본문 스크롤만 반응.
    if (n.metrics.axis != Axis.vertical) return false;
    // 헤더가 밀려날 만큼 스크롤되기 전(상단 근처)엔 항상 표시.
    if (n.metrics.pixels < 64) {
      _setChromeShown(true, spring: MotionSprings.standard);
      return false;
    }
    if (n.direction == ScrollDirection.reverse) {
      _setChromeShown(false, spring: MotionSprings.standard);
    } else if (n.direction == ScrollDirection.forward) {
      _setChromeShown(true, spring: MotionSprings.bounce);
    }
    return false;
  }

  ProfileData? _profile;
  int _pendingInvites = 0;
  bool _loading = true;
  String? _error;

  // 업체 모드 히어로용 후기 요약(일반 모드면 null).
  int? _bizReviewCount;
  double? _bizReviewAvg;

  // 내가 작성한 게시글 — 공개 프로필과 동일한 2열 그리드로 표시.
  List<Post> _myPosts = [];
  final _postKeys = <String, GlobalKey>{};
  String? _openedPostId;

  // 프로필 히어로 카드 → 수정 화면 확장 전환용.
  final _profileCardKey = GlobalKey();

  Rect? _profileRect() {
    final box =
        _profileCardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 프로필 카드 탭 → 카드 자리에서 수정 화면이 펼쳐진다(글쓰기 버튼과 동일한 전환).
  Future<void> _openProfileEdit() async {
    final p = _profile;
    if (p == null) return;
    final rect = _profileRect();
    final page = ProfileEditScreen(
      initialNickname: p.nickname,
      initialAddress: p.address,
      initialVerified: p.isLocationVerified,
      profile: p,
      pendingInvites: _pendingInvites,
    );
    await Navigator.push(
      context,
      rect == null
          ? AppPageRoute(builder: (_) => page)
          : ExpandRoute(
              originRect: rect,
              originRadius: 24, // 프로필 히어로 카드 곡률과 동일
              builder: (_) => page,
              origin: (_) => _ProfileHeroCard(
                profile: p,
                bizReviewCount: _bizReviewCount,
                bizReviewAvg: _bizReviewAvg,
              ),
            ),
    );
    if (mounted) _load(silent: true); // 닉네임 등 수정 반영
  }

  // ── 내 게시글: 대표사진 2열 그리드 (공개 프로필과 동일) ──

  Rect? _postRect(String id) {
    final box = _postKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openPost(Post post) async {
    final rect = _postRect(post.id);
    final page = PostDetailScreen(
      post: post,
      originRect: rect,
      cardBuilder: rect == null ? null : (_) => PostPhotoTile(post: post),
      cardRadius: 16, // PostPhotoTile 곡률과 동일.
      // 내 글 작성자(나) 탭은 프로필을 쌓지 않고 되돌아온다(무한 왕복 방지).
      fromUserId: SessionManager.instance.user?.id,
    );
    if (rect != null) setState(() => _openedPostId = post.id);
    await Navigator.push(
      context,
      rect == null
          ? AppPageRoute(builder: (_) => page)
          : CollapseRoute(builder: (_) => page),
    );
    if (!mounted) return;
    setState(() => _openedPostId = null);
    _load(silent: true); // 하트/댓글/삭제 변동 반영
  }

  Widget _myPostsSection({bool isBusinessMode = false}) {
    final posts = _myPosts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                isBusinessMode ? '업체 게시글' : '내 게시글',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
              if (posts.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${posts.length}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isBusinessMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Text(
              '업체 모드로 작성한 게시글만 보여요',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (posts.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: context.colors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                isBusinessMode ? '업체 모드로 작성한 게시글이 없어요' : '작성한 게시글이 없어요',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: posts.length,
              itemBuilder: (_, i) {
                final post = posts[i];
                // 상세가 열린 타일은 빈자리로 — 축소가 겹침 없이 안착.
                return Opacity(
                  key: _postKeys.putIfAbsent(post.id, GlobalKey.new),
                  opacity: _openedPostId == post.id ? 0 : 1,
                  child: PostPhotoTile(
                    post: post,
                    onTap: () => _openPost(post),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _load();
      AppEvents.instance.social.addListener(_onSocialChanged);
      AppEvents.instance.profile.addListener(_onSocialChanged);
    }
  }

  @override
  void dispose() {
    _chromeCtrl.dispose();
    AppEvents.instance.social.removeListener(_onSocialChanged);
    AppEvents.instance.profile.removeListener(_onSocialChanged);
    super.dispose();
  }

  void _onSocialChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await ProfileRepository.instance.fetchProfile();
      int invites = 0;
      try {
        invites = await PetRepository.instance.pendingInviteCount();
      } catch (_) {}
      var posts = _myPosts;
      try {
        final uid = SessionManager.instance.user?.id;
        if (uid != null) {
          // 같은 계정이지만 분리된 프로필 — 현재 모드로 작성한 글만 (0025 후속)
          posts = await CommunityRepository.instance.fetchUserPosts(
            uid,
            authoredAs: p.activeMode,
          );
        }
      } catch (_) {} // 게시글 조회 실패 시 기존 목록 유지
      // 업체 모드 히어로의 후기 요약(후기 수·평점)
      int? bizCount;
      double? bizAvg;
      if (p.activeMode == 'business') {
        try {
          final rs = await BusinessRepository.instance
              .fetchMyFacilityReviews();
          bizCount = rs.length;
          bizAvg = rs.isEmpty
              ? null
              : rs.map((r) => r.rating).reduce((a, b) => a + b) / rs.length;
        } catch (_) {
          bizCount = 0;
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = p;
        _pendingInvites = invites;
        _myPosts = posts;
        _bizReviewCount = bizCount;
        _bizReviewAvg = bizAvg;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 조용한 새로고침 실패 시 기존 데이터 유지
        if (_profile == null) _error = '프로필을 불러오지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) return const _GuestMyInfo();

    final topInset = MediaQuery.of(context).padding.top;
    // 다른 탭(채팅·검색·커뮤니티)과 동일하게: 콘텐츠가 떠 있는 프로스트 헤더
    // 아래로 스크롤되며 비치는 구조.
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _onUserScroll,
              child: _buildBody(topInset + 56),
            ),
          ),
          // 헤더 — 아래로 스크롤 시 위로 밀려 숨고, 위로 올리면 스프링 복귀
          // (하단 네비 바와 같은 신호로 동기화).
          AnimatedBuilder(
            animation: _chromeCtrl,
            builder: (context, child) {
              final hidden = 1 - _chromeCtrl.value.clamp(0.0, 1.0);
              return GradientHeader(
                topInset: topInset,
                shift: hidden * (topInset + 72),
                child: child!,
              );
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                '내 정보',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primaryDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double topPad) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? '프로필을 불러오지 못했어요',
              style: TextStyle(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    final profile = _profile!;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: topPad,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        // 헤더 아래에서 시작, 하단은 플로팅 메뉴바(62 + 아래 8) 위 16 간격까지만 —
        // 필요 이상 위로 오버스크롤되지 않게 여백을 최소로 잡는다.
        padding: EdgeInsets.only(
          top: topPad + 14,
          bottom: 62 + bottomInset + 8 + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 업체 모드는 분리된 프로필 — 반려동물 히어로 없이 업체 정보가 주인공
            // (같은 계정이어도 두 얼굴이 섞이지 않게, 0025 후속).
            if (profile.activeMode != 'business') ...[
              // 반려동물이 주인공 — 큰 히어로 카드/캐러셀을 최상단에.
              _PetHero(pets: profile.pets),
              const SizedBox(height: 20),
            ] else
              // 업체 모드: 펫 히어로가 빠져 헤더와 프로필 카드가 붙어 보임 — 숨 고를 간격.
              const SizedBox(height: 12),
            // 유저 정보 — 다른 사용자가 보는 공개 프로필 헤더와 동일한 히어로 카드.
            // 탭하면 그 자리에서 프로필 수정 화면으로 펼쳐진다.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: KeyedSubtree(
                key: _profileCardKey,
                child: _ProfileHeroCard(
                  profile: profile,
                  onTap: _openProfileEdit,
                  bizReviewCount: _bizReviewCount,
                  bizReviewAvg: _bizReviewAvg,
                  // 약속(산책·돌봄 매칭)은 개인 활동 — 업체 모드엔 캘린더 숨김.
                  onCalendarTap: profile.activeMode == 'business'
                      ? null
                      : () => Navigator.push(
                          context,
                          AppPageRoute(
                            builder: (_) => const MyAppointmentsScreen(),
                          ),
                        ),
                  // Pawing/Pawmate 숫자 탭 → 연결 목록(뷰가 현재 얼굴 기준 필터).
                  onOpenConnections: (i) => Navigator.push(
                    context,
                    AppPageRoute(
                      builder: (_) => ConnectionsScreen(initialIndex: i),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // 업체 모드: 내 업소에 달린 후기 관리 — 프로필 바로 아래.
            if (profile.activeMode == 'business') ...[
              const _BusinessReviewsSection(),
              const SizedBox(height: 28),
            ],
            // 내가 작성한 게시글 — 공개 프로필과 동일한 2열 사진 그리드.
            // 현재 모드로 작성한 글만 보인다(모드 분리).
            // (내 활동·활동 범위·관심·설정은 프로필 수정 화면으로 이동)
            // 약관·처리방침 열람은 내정보 수정 화면의 '약관 및 정책' 항목에서
            // (게스트 화면 푸터는 유지 — 로그인 전 접근 경로).
            _myPostsSection(isBusinessMode: profile.activeMode == 'business'),
          ],
        ),
      ),
    );
  }
}

/// 업체 후기 — 내 업소(공공데이터 매칭 시설)에 타 사용자가 남긴 시설 후기 관리 UI.
/// 매칭 시설이 없으면(신규개업 등) 그 사실을 안내한다.
class _BusinessReviewsSection extends StatefulWidget {
  const _BusinessReviewsSection();

  @override
  State<_BusinessReviewsSection> createState() =>
      _BusinessReviewsSectionState();
}

class _BusinessReviewsSectionState extends State<_BusinessReviewsSection> {
  List<BizFacilityReview>? _reviews; // null = 로딩 중

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reviews = await BusinessRepository.instance.fetchMyFacilityReviews();
    if (mounted) setState(() => _reviews = reviews);
  }

  @override
  Widget build(BuildContext context) {
    final reviews = _reviews;
    final avg = (reviews == null || reviews.isEmpty)
        ? null
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) /
              reviews.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                '업체 후기',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
              if (reviews != null && reviews.isNotEmpty) ...[
                const SizedBox(width: 8),
                // 별점 색은 시설 후기 화면과 동일 컨벤션.
                const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFB300)),
                Text(
                  '${avg!.toStringAsFixed(1)} · ${reviews.length}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (reviews == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (reviews.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: context.colors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '아직 후기가 없어요\n지도 시설에 연결된 업체는 방문자 후기가 여기에 모여요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
          )
        else
          // 사진+평점 카드 그리드 — 탭하면 상세 시트(지도 상세와 동일 언어).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ReviewCardGrid(
              reviews: [
                for (final r in reviews)
                  ReviewCardData(
                    author: r.authorNickname,
                    rating: r.rating,
                    content: r.content,
                    createdAt: r.createdAt,
                    photoUrls: r.photoUrls,
                    visitNo: r.visitNo,
                    seed: r.id,
                    reviewId: r.id,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GuestMyInfo extends StatelessWidget {
  const _GuestMyInfo();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: context.colors.primarySoft,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 48,
                  color: context.colors.primaryDark,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '게스트로 둘러보는 중',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '회원이 되면 반려동물 등록·산책 메이트 매칭·\n채팅까지 모두 이용할 수 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => const SignupPhoneScreen()),
                ),
                child: const Text('전화번호로 시작하기'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text('로그인'),
              ),
              const Spacer(),
              const _GuestFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestFooter extends StatelessWidget {
  const _GuestFooter();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      children: [
        _link(context, '이용약관', TermsScreen.service()),
        _link(context, '위치기반서비스 약관', TermsScreen.location()),
        _link(context, '개인정보 처리방침', TermsScreen.privacy()),
      ],
    );
  }

  Widget _link(BuildContext context, String s, Widget screen) =>
      GestureDetector(
        onTap: () => _push(context, screen),
        child: Text(
          s,
          style: TextStyle(
            fontSize: 12,
            color: context.colors.textTertiary,
            decoration: TextDecoration.underline,
          ),
        ),
      );
}

/// 반려동물 히어로 — 내정보 최상단의 주인공. 큰 사진 카드(여러 마리면 캐러셀).
class _PetHero extends StatefulWidget {
  final List<MockPet> pets;
  const _PetHero({required this.pets});

  @override
  State<_PetHero> createState() => _PetHeroState();
}

class _PetHeroState extends State<_PetHero> {
  final _pc = PageController(viewportFraction: 0.9);
  int _page = 0;

  // 카드 → 펫 상세 확장 전환용(게시글 상세와 동일 패턴).
  final _cardKeys = <String, GlobalKey>{};
  String? _openedPetId;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _openEditor() => _push(context, const PetEditScreen());

  Rect? _cardRect(String id) {
    final box = _cardKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 카드 자리에서 펫 상세가 펼쳐지고/당기면 카드로 축소된다.
  Future<void> _openPet(MockPet pet) async {
    final rect = _cardRect(pet.id);
    final page = PetDetailScreen(
      pet: pet,
      originRect: rect,
      cardBuilder: rect == null
          ? null
          : (_) => _PetHeroCard(pet: pet, onTap: () {}),
    );
    if (rect != null) setState(() => _openedPetId = pet.id);
    await Navigator.push(
      context,
      rect == null
          ? AppPageRoute(builder: (_) => page)
          : CollapseRoute(builder: (_) => page),
    );
    if (mounted) setState(() => _openedPetId = null);
  }

  @override
  Widget build(BuildContext context) {
    final pets = widget.pets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: Row(
            children: [
              Text(
                '내 반려동물',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
              if (pets.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${pets.length}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textTertiary,
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('등록'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (pets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: EmptyPetCard(onTap: _openEditor),
          )
        else ...[
          SizedBox(
            height: 320,
            child: PageView.builder(
              controller: _pc,
              // 항상 양끝 여백 — 한 마리(viewportFraction 0.9)일 때도 카드가
              // 왼쪽에 붙지 않고 중앙에 오게(여러 마리는 캐러셀 중앙 정렬).
              padEnds: true,
              itemCount: pets.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final pet = pets[i];
                final key = _cardKeys.putIfAbsent(pet.id, () => GlobalKey());
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: KeyedSubtree(
                    key: key,
                    // 상세로 열려있으면 투명(빈자리) — 축소가 겹침 없이 안착.
                    child: Opacity(
                      opacity: pet.id == _openedPetId ? 0.0 : 1.0,
                      child: _PetHeroCard(pet: pet, onTap: () => _openPet(pet)),
                    ),
                  ),
                );
              },
            ),
          ),
          if (pets.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pets.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? context.colors.primaryDark
                          : context.colors.border,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// 반려동물 히어로 카드 — 큰 사진 위에 이름/종·나이/인증 배지를 오버레이(포스터형).
class _PetHeroCard extends StatelessWidget {
  final MockPet pet;
  final VoidCallback onTap;
  const _PetHeroCard({required this.pet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final age = pet.birthDate == null
        ? null
        : '${DateTime.now().year - pet.birthDate!.year}살';
    final genderKo = switch (pet.gender) {
      'male' => '남아',
      'female' => '여아',
      _ => null,
    };
    final subtitle = [
      pet.species,
      if (age != null) age,
      if (genderKo != null) genderKo,
    ].join('  ·  ');

    // Pressable — 피드 카드·검색 타일과 동일한 스프링 눌림 피드백으로 통일.
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.colors.primarySoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 사진(없으면 발바닥 플레이스홀더)
            if (pet.imageUrl != null)
              Image.network(
                pet.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _PetHeroPlaceholder(),
              )
            else
              const _PetHeroPlaceholder(),
            // 하단 어둡게 — 흰 글씨 가독성.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
              ),
            ),
            // 상단 우측: 역할 + 인증 배지
            Positioned(
              top: 14,
              right: 14,
              child: Row(
                children: [
                  if (pet.isIdentityVerified) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified,
                            size: 13,
                            color: context.colors.primaryDark,
                          ),
                          SizedBox(width: 3),
                          Text(
                            '인증',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.colors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  RoleBadge(role: pet.role, compact: true),
                ],
              ),
            ),
            // 하단 좌측: 이름 + 종·나이·성별
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xF2FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PetHeroPlaceholder extends StatelessWidget {
  const _PetHeroPlaceholder();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.primarySoft,
    child: Center(
      child: Icon(Icons.pets, size: 72, color: context.colors.primaryDark),
    ),
  );
}

/// 유저 프로필 히어로 — 다른 사용자가 보는 공개 프로필 헤더 카드와 동일한 디자인
/// (애플뮤직 스타일: 사진 풀블리드 + 하단 점진 블러 + 닉네임/유형·지역/통계).
/// 사진이 없으면 primaryDark 배경에 닉네임을 크게. 탭하면 프로필 수정으로 펼쳐진다.
class _ProfileHeroCard extends StatelessWidget {
  final ProfileData profile;
  final VoidCallback? onTap;
  // 업체 모드 히어로의 방문 후기 요약(null = 미로딩/일반 모드).
  final int? bizReviewCount;
  final double? bizReviewAvg;

  /// 사진 우측 상단 약속 캘린더 바로가기(null 이면 버튼 없음 — 전환 고스트 등).
  final VoidCallback? onCalendarTap;

  /// Pawing(0)·Pawmate(1) 숫자 탭 → 연결 목록(현재 얼굴 기준). 개인·업체 공용.
  final void Function(int index)? onOpenConnections;

  const _ProfileHeroCard({
    required this.profile,
    this.onTap,
    this.bizReviewCount,
    this.bizReviewAvg,
    this.onCalendarTap,
    this.onOpenConnections,
  });

  @override
  Widget build(BuildContext context) {
    // 얼굴별 사진 분리(0026) — 업체 모드 히어로는 대표 사진(개인 사진 미사용).
    final photo = profile.activeMode == 'business'
        ? profile.businessPhotoUrl
        : profile.profileImageUrl;
    final hasPhoto = photo != null;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 360, // 공개 프로필 헤더 카드와 동일 높이
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.colors.primaryDark,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              Image.network(
                photo,
                fit: BoxFit.cover,
                cacheWidth: 1200,
                errorBuilder: (_, _, _) => _noPhotoBackground(context),
              )
            else
              _noPhotoBackground(context),
            // 점진 블러 — 공개 프로필 헤더와 동일 문법.
            if (hasPhoto)
              Positioned.fill(
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0x00FFFFFF),
                      Color(0xFFFFFFFF),
                    ],
                    stops: [0.0, 0.5, 0.88],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 22,
                      sigmaY: 22,
                      tileMode: ui.TileMode.clamp,
                    ),
                    child: Image.network(
                      photo,
                      fit: BoxFit.cover,
                      cacheWidth: 400, // 블러 사본 — 저해상 디코딩으로 충분
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            // 가독용 스크림.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 150,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x4D000000)],
                  ),
                ),
              ),
            ),
            // 사진 우측 상단 — 약속 캘린더 바로가기(상세 화면들의 오버레이 버튼 문법).
            if (onCalendarTap != null)
              Positioned(
                top: 10,
                right: 10,
                width: 40,
                height: 40,
                child: OverlayIconButton(
                  icon: Icons.calendar_month_rounded,
                  tooltip: '약속 일정',
                  onPressed: onCalendarTap!,
                ),
              ),
            // 정보 — 블러 구간 위.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasPhoto) ...[
                      Text(
                        // 업체 '모드'일 때만 상호가 이름 자리에 — 상호는 이제 상시
                        // 공개(0026 §2 개정)라 null 여부가 아닌 모드로 판별한다.
                        profile.activeMode == 'business'
                            ? (profile.businessName ?? profile.nickname)
                            : profile.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    _metaLine(),
                    const SizedBox(height: 10),
                    // 업체 모드: 방문 후기 요약(후기 수·평점) + Pawing·Pawmate.
                    // Pawmate 는 업체 얼굴 팔로워 기준으로 이미 분리 집계된다.
                    if (profile.activeMode == 'business')
                      (bizReviewCount == null || bizReviewCount == 0)
                          // 후기 없음: 안내 + Pawing/Pawmate 2칸.
                          ? Column(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '아직 후기가 없어요',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xCCFFFFFF),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _statCol(
                                        'Pawing',
                                        profile.pawingCount,
                                        onTap: () => onOpenConnections?.call(0),
                                      ),
                                    ),
                                    _statDivider(),
                                    Expanded(
                                      child: _statCol(
                                        'Pawmate',
                                        profile.pawmateCount,
                                        onTap: () => onOpenConnections?.call(1),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          // 후기 있음: 후기·평점·Pawing·Pawmate 4칸.
                          : Row(
                              children: [
                                Expanded(
                                  child: _statCol('후기', bizReviewCount!),
                                ),
                                _statDivider(),
                                Expanded(
                                  child: _ratingCol(
                                    bizReviewAvg?.toStringAsFixed(1) ?? '-',
                                  ),
                                ),
                                _statDivider(),
                                Expanded(
                                  child: _statCol(
                                    'Pawing',
                                    profile.pawingCount,
                                    onTap: () => onOpenConnections?.call(0),
                                  ),
                                ),
                                _statDivider(),
                                Expanded(
                                  child: _statCol(
                                    'Pawmate',
                                    profile.pawmateCount,
                                    onTap: () => onOpenConnections?.call(1),
                                  ),
                                ),
                              ],
                            )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _statCol('받은 후기', profile.reviewCount),
                          ),
                          _statDivider(),
                          Expanded(
                            child: _statCol(
                              'Pawing',
                              profile.pawingCount,
                              onTap: () => onOpenConnections?.call(0),
                            ),
                          ),
                          _statDivider(),
                          Expanded(
                            child: _statCol(
                              'Pawmate',
                              profile.pawmateCount,
                              onTap: () => onOpenConnections?.call(1),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사진 없는 프로필 — 닉네임을 카드 중앙에 크게(공개 프로필과 동일).
  Widget _noPhotoBackground(BuildContext context) => ColoredBox(
    color: context.colors.primaryDark,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 100, left: 24, right: 24),
        child: Text(
          profile.activeMode == 'business'
              ? (profile.businessName ?? profile.nickname)
              : profile.nickname,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: context.colors.textOnPrimary,
          ),
        ),
      ),
    ),
  );

  Widget _metaLine() {
    final region = profile.regionName;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // 배지는 업체 모드에서만 — 개인 얼굴엔 업체 흔적을 남기지 않는다(0025 연결 차단)
          profile.activeMode == 'business'
              ? '인증 업체'
              : _userTypeLabel(profile.userType),
          style: const TextStyle(fontSize: 12, color: Color(0xE6FFFFFF)),
        ),
        if (region != null) ...[
          const SizedBox(width: 8),
          const Icon(Icons.location_on, size: 12, color: Color(0xE6FFFFFF)),
          const SizedBox(width: 2),
          Text(
            region,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xE6FFFFFF),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: const Color(0x4DFFFFFF));

  Widget _ratingCol(String value) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFB300)),
          const SizedBox(width: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
      const SizedBox(height: 1),
      const Text(
        '평점',
        style: TextStyle(fontSize: 10, color: Color(0xCCFFFFFF)),
      ),
    ],
  );

  Widget _statCol(String label, int value, {VoidCallback? onTap}) {
    final col = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xCCFFFFFF)),
        ),
      ],
    );
    if (onTap == null) return col;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: col,
    );
  }

  // 'business' 는 백필 전 레거시 계정 표시용으로만 남김 — 신규는 is_business 배지 (0025 §1.1)
  String _userTypeLabel(String t) => switch (t) {
    'pet_owner' => '반려동물 보호자',
    'no_pet' => '반려동물 미보유',
    'business' => '업체',
    'admin' => '관리자',
    _ => t,
  };
}
