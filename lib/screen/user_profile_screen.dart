import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../models/community.dart';
import '../models/profile.dart';
import '../services/community_repository.dart';
import '../services/profile_repository.dart';
import '../services/social_repository.dart';
import '../services/chat_launcher.dart';
import '../services/session.dart';
import '../data/mock_data.dart' show MockPet;
import '../widgets/role_badge.dart' show categoryColor;
import '../widgets/blob_background.dart';
import 'pet_profile_screen.dart';
import 'post_detail_screen.dart';

/// 타 사용자 공개 프로필 — 사용자 검색/연결 목록에서 진입.
/// 프로필 헤더(사진·지역·통계) + 반려동물 포스터 + 받은 평가 + 작성 게시글.
/// [originRect] 가 있으면 검색 타일에서 펼쳐지고/당기면 그 자리로 축소된다
/// (커뮤니티 게시글 상세와 동일한 전환 언어).
class UserProfileScreen extends StatefulWidget {
  final String userId;

  /// 로딩 전 즉시 보여줄 닉네임(선택).
  final String? previewNickname;

  /// 검색 타일에서 펼쳐지는 전환용. null 이면 일반 화면.
  final Rect? originRect;

  /// 축소 시 크로스페이드로 나타날 원본 타일(검색 결과와 동일 위젯).
  final WidgetBuilder? cardBuilder;

  /// 원본 타일의 모서리 곡률 — 축소 안착 시 곡률이 튀지 않도록 타일과 맞춘다.
  final double cardRadius;

  /// 이 화면으로 들어오기 직전에 보던 반려동물 id(있으면). 그 펫을 다시 열려 하면
  /// 새 화면을 쌓지 않고 pop 으로 되돌아간다(A→펫→A 무한 스택 방지).
  final String? fromPetId;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.previewNickname,
    this.originRect,
    this.cardBuilder,
    this.cardRadius = 16,
    this.fromPetId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicProfileData? _profile;
  List<Post> _posts = [];
  bool _loading = true;
  bool _error = false;

  bool _following = false;
  bool _followBusy = false;

  // CollapsibleView(당겨서 축소) 용 스크롤 컨트롤러.
  final _scroll = ScrollController();

  // 게시글 카드 → 상세 확장 전환용(커뮤니티와 동일 패턴).
  final _postKeys = <String, GlobalKey>{};
  String? _openedPostId;

  // 반려동물 포스터 확장/축소 — 게시글 상세와 동일 전환.
  String? _openedPetId;

  // 섹션 타이틀 위치 캡처 — 도킹 판정 + 타이틀 탭 시 해당 섹션으로 스크롤 이동용.
  final _titleKeys = List.generate(3, (_) => GlobalKey());
  final List<double?> _titleReveal = [null, null, null];

  bool get _isMe => widget.userId == SessionManager.instance.user?.id;

  @override
  void initState() {
    super.initState();
    _load();
    if (!_isMe) _loadFollowing();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final results = await Future.wait([
        ProfileRepository.instance.fetchPublicProfile(widget.userId),
        CommunityRepository.instance
            .fetchUserPosts(widget.userId)
            .catchError((_) => const <Post>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as PublicProfileData;
        _posts = results[1] as List<Post>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = true;
      });
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final f = await SocialRepository.instance.isFollowing(widget.userId);
      if (mounted) setState(() => _following = f);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    final was = _following;
    setState(() {
      _followBusy = true;
      _following = !was;
    });
    try {
      if (was) {
        await SocialRepository.instance.unfollow(widget.userId);
      } else {
        await SocialRepository.instance.follow(widget.userId);
      }
    } catch (_) {
      if (mounted) setState(() => _following = was);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  String _userTypeLabel(String t) => switch (t) {
    'pet_owner' => '반려동물 보호자',
    'no_pet' => '반려동물 미보유',
    'business' => '업체',
    'admin' => '관리자',
    _ => t,
  };

  // ── 게시글 상세: 카드 자리에서 펼쳐지고/당기면 축소 (커뮤니티와 동일) ──

  Rect? _postRect(String id) {
    final ctx = _postKeys[id]?.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
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
    );
    if (rect != null) setState(() => _openedPostId = post.id);
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page)
          : CollapseRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    setState(() => _openedPostId = null);
    _load(silent: true); // 하트/댓글 변동 반영
  }

  Future<void> _openPet(MockPet pet, Rect? rect) async {
    // 방금 거쳐온 펫이면 새로 쌓지 않고 되돌아간다(무한 왕복 방지).
    if (pet.id == widget.fromPetId) {
      // maybePop → CollapsibleView(PopScope)가 축소 애니메이션을 태운 뒤 팝.
      Navigator.of(context).maybePop();
      return;
    }
    final page = PetProfileScreen(
      petId: pet.id,
      fromUserId: widget.userId,
      originRect: rect,
      cardBuilder: rect == null ? null : (_) => PetPosterCard(pet: pet),
      cardRadius: 24, // PetPosterCard 곡률과 동일.
    );
    if (rect != null) setState(() => _openedPetId = pet.id);
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page)
          : CollapseRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    setState(() => _openedPetId = null);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    // 검색 타일에서 펼쳐지고/당기면 타일로 축소 — 게시글 상세와 동일 래퍼.
    // 상단바 없는 몰입형: 사용자 정보 카드만 최상단에 핀 고정된 채 제자리 수축하고,
    // 섹션 타이틀·내용은 함께 스크롤되어 그 뒤로 지나간다.
    return CollapsibleView(
      originRect: widget.originRect,
      card: widget.cardBuilder,
      cardRadius: widget.cardRadius,
      scrollController: _scroll,
      builder: (context, physics) => Scaffold(
        backgroundColor: Colors.white,
        body: _buildBody(physics, topInset),
      ),
    );
  }

  Widget _buildBody(ScrollPhysics physics, double topInset) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error || _profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '프로필을 불러오지 못했어요',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    final p = _profile!;
    // 갈색 사용자 정보 카드는 최상단 핀 고정 — 그 자리에서 닉네임 바로 수축.
    // 섹션 타이틀 3개는 스크롤에 따라 계단으로 도킹되고, 마지막 계단까지 쌓인
    // 뒤에는 계단 전체가 콘텐츠와 함께 위로 밀려 닉네임 바 뒤로 사라진다.
    // 타이틀을 탭하면 그 섹션 위치로, 닉네임을 탭하면 최상단으로 이동.
    final headerMax = topInset + 8 + _kHeaderCardH + 12;
    final titles = [
      ('키우는 반려동물', p.pets.length),
      ('받은 평가', p.reviewCount),
      ('작성한 게시글', _posts.length),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) {
              // 콘텐츠가 짧아도 헤더가 끝까지 접힐 스크롤 거리를 보장 —
              // 본문 최소 높이 = 뷰포트 + 접힘 거리 − 상하 패딩.
              final collapseRange = _kHeaderCardH - _kHeaderBarH;
              final minBodyH = (box.maxHeight + collapseRange - headerMax - 40)
                  .clamp(0.0, double.infinity);
              return SingleChildScrollView(
                controller: _scroll,
                physics: physics,
                padding: EdgeInsets.only(top: headerMax, bottom: 40),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minBodyH),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isMe)
                        Entrance(
                          index: 0,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: _actions(p),
                          ),
                        ),
                      const SizedBox(height: 20),
                      _inlineTitle(0, titles),
                      Entrance(index: 1, child: _petContent(p)),
                      const SizedBox(height: 24),
                      _inlineTitle(1, titles),
                      Entrance(index: 2, child: _reviewContent(p)),
                      const SizedBox(height: 24),
                      _inlineTitle(2, titles),
                      Entrance(index: 3, child: _postContent()),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // 상단 핀: 사용자 정보 헤더(수축)만 고정 — 콘텐츠가 그 뒤로 지나간다.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: _scroll,
            builder: (context, _) => _pinnedHeader(p, topInset),
          ),
        ),
      ],
    );
  }

  // ── 핀 스택(오버레이) 계산 ──
  // 헤더: offset 에 따라 카드(360) → 닉네임 바(48)로 제자리 수축.
  // 타이틀 i: 인라인 위치가 [헤더 바닥 + 44*i] 라인에 닿으면 도킹(계단 3개).
  // 마지막 계단까지 도킹된 뒤(릴리즈 지점)에는 계단 스택 전체가 콘텐츠와 함께
  // 위로 밀려 닉네임 바 뒤로 사라진다 — 닉네임만 남고 전체가 스크롤되는 구조.

  static const double _kHeaderCardH = 360; // 대표사진 히어로 카드(애플뮤직 스타일)
  static const double _kHeaderBarH = 48;
  static const double _kTitleH = 44;

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;

  /// 현재 헤더 아래 라인(뷰포트 좌표) — 카드가 다 수축하면 바 높이로 고정.
  double _headerBottom(double topInset) {
    final shrunk = (_kHeaderCardH - _offset).clamp(_kHeaderBarH, _kHeaderCardH);
    return topInset + 8 + shrunk + 12;
  }

  /// 타이틀 i 의 도킹 여부 — 인라인 타이틀 상단(뷰포트 y)이 자기 슬롯 라인 이하.
  bool _isDocked(int i, double topInset) {
    final reveal = _titleReveal[i];
    if (reveal == null) return false;
    final y = reveal - _offset; // 인라인 타이틀의 뷰포트 y
    return y <= _headerBottom(topInset) + _kTitleH * i;
  }

  void _measureTitles() {
    if (!mounted) return;
    for (var i = 0; i < _titleKeys.length; i++) {
      final box = _titleKeys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      _titleReveal[i] = viewport.getOffsetToReveal(box, 0).offset;
    }
  }

  /// 섹션 타이틀 탭 → 그 타이틀이 자기 슬롯(닉네임 바 + 위 계단들 아래)에
  /// 오도록 스크롤. 마지막 타이틀은 도킹된 두 계단 바로 아래 라인에 정렬.
  void _scrollToSection(int i) {
    final box = _titleKeys[i].currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final reveal = viewport.getOffsetToReveal(box, 0).offset;
    final topInset = MediaQuery.paddingOf(context).top;
    // 도착 시점의 헤더는 완전 수축(바) 상태 — 바 + 자기 위 계단 수만큼 내린 라인.
    final target = (reveal - (topInset + 8 + _kHeaderBarH + 12 + _kTitleH * i))
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  /// 닉네임(헤더) 탭 → 최상단으로.
  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  /// 리스트 안의 인라인 타이틀 — 도킹되면 숨겨 오버레이 복제와 겹치지 않게 하고,
  /// 탭하면 그 섹션 위치로 스크롤한다.
  Widget _inlineTitle(int i, List<(String, int)> titles) {
    // 위쪽 콘텐츠(로딩/이미지)로 위치가 바뀔 수 있어 매 프레임 뒤 갱신(값 대입뿐).
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTitles());
    final topInset = MediaQuery.of(context).padding.top;
    return KeyedSubtree(
      key: _titleKeys[i],
      child: AnimatedBuilder(
        animation: _scroll,
        builder: (context, child) =>
            Opacity(opacity: _isDocked(i, topInset) ? 0 : 1, child: child),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _scrollToSection(i),
          child: _titleBar(titles[i].$1, titles[i].$2),
        ),
      ),
    );
  }

  /// 상단 핀 스택 — 헤더(수축) + 도킹된 계단 타이틀(3개).
  /// 마지막 계단까지 도킹되면(릴리즈) 계단 스택 전체가 스크롤을 따라 위로 밀려
  /// 닉네임 바 뒤로 사라진다. 도킹된 타이틀도 탭하면 그 섹션 위치로 이동한다.
  Widget _pinnedHeader(PublicProfileData p, double topInset) {
    final t = ((_offset) / (_kHeaderCardH - _kHeaderBarH)).clamp(0.0, 1.0);
    final titles = [
      ('키우는 반려동물', p.pets.length),
      ('받은 평가', p.reviewCount),
      ('작성한 게시글', _posts.length),
    ];
    // 릴리즈 지점 = 마지막 타이틀이 자기 슬롯에 도킹 완료되는 오프셋.
    final base = topInset + 8 + _kHeaderBarH + 12; // 완전 수축 시 헤더 바닥
    final lastReveal = _titleReveal[titles.length - 1];
    final release = lastReveal == null
        ? double.infinity
        : lastReveal - base - _kTitleH * (titles.length - 1);
    final slide = (_offset - release).clamp(0.0, double.infinity);
    final headerBottomPx = _headerBottom(topInset);
    // 가림판 높이 — 계단 스택 위쪽(이미 지나간 섹션 내용)을 흰색으로 덮는다.
    // 릴리즈 후 스택이 올라가는 만큼 같이 걷혀, 스택이 지나간 자리부터는
    // 현재 흐름의 콘텐츠가 닉네임 바 뒤로 그대로 비친다.
    final backingH = (headerBottomPx - slide).clamp(0.0, headerBottomPx);

    return Stack(
      children: [
        // 스테일 콘텐츠 가림판 — 계단·헤더보다 먼저 그린다(밑에 깔림).
        if (backingH > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: backingH,
            child: const AbsorbPointer(
              child: ColoredBox(color: Colors.white),
            ),
          ),
        // 계단 스택 — 릴리즈 후엔 콘텐츠와 같은 속도(-slide)로 올라가며 클립 없이
        // 닉네임 바 뒤로 자연스럽게 지나간다(바가 덮는 부분만 가려짐).
        Padding(
          padding: EdgeInsets.only(top: headerBottomPx),
          child: Transform.translate(
            offset: Offset(0, -slide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < titles.length; i++)
                  if (_isDocked(i, topInset))
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _scrollToSection(i),
                      child: _titleBar(titles[i].$1, titles[i].$2),
                    ),
              ],
            ),
          ),
        ),
        _headerBox(p, t, topInset),
      ],
    );
  }

  /// 섹션 타이틀 바 — 인라인/도킹 공용(같은 모양이라 스왑이 안 보인다).
  Widget _titleBar(String label, int count) {
    return Container(
      height: _kTitleH,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 사용자 정보 헤더 — 제자리 수축: 카드(사진·지역·통계) → 닉네임만 남은 긴 바.
  /// 탭하면 최상단으로 스크롤.
  Widget _headerBox(PublicProfileData p, double t, double topInset) {
    final h = _kHeaderCardH - (_kHeaderCardH - _kHeaderBarH) * t;
    final fullOpacity = (1 - t * 1.8).clamp(0.0, 1.0);
    final barOpacity = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    final radius = 24.0 + (100.0 - 24.0) * t;

    // 자체 배경판 없음 — 스테일 콘텐츠 가림은 _pinnedHeader 의 가림판이 담당.
    // 닉네임 바(불투명 브라운)만 남고, 주변으로는 계단·콘텐츠가 지나가는 게
    // 보인다. 탭은 바 위에서만 받는다(최상단 이동).
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _scrollToTop,
        child: Container(
          height: h,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (fullOpacity > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _kHeaderCardH,
                  child: Opacity(
                    opacity: fullOpacity,
                    child: _fullHeaderCard(p),
                  ),
                ),
              if (barOpacity > 0)
                Opacity(
                  opacity: barOpacity,
                  child: Center(
                    child: Text(
                      p.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 애플뮤직 아티스트 카드 스타일 — 대표사진이 카드를 가득 채우고, 하단은
  /// 사진을 이어받아 점진 블러 처리된 구간에 닉네임·활동지역·통계를 올린다.
  /// 사진이 없으면 닉네임을 카드 중앙에 크게 넣고, 블러 구간에는 닉네임을 뺀다.
  Widget _fullHeaderCard(PublicProfileData p) {
    final hasPhoto = p.profileImageUrl != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasPhoto)
          Image.network(
            p.profileImageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _noPhotoBackground(p),
          )
        else
          _noPhotoBackground(p),
        // 점진 블러 — 같은 사진의 블러 사본을 세로 그라데이션 마스크로 페이드인.
        // 아래로 갈수록 블러 사본이 진해져 경계선 없이 연속적으로 뭉개진다(am 스타일).
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
                  p.profileImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        // 가독용 스크림 — 부드러운 단일 그라데이션.
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
        // 정보 — 블러 구간 위에 올라간다.
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
                    p.nickname,
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
                _metaLine(p),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _statCol('받은 평가', p.reviewCount)),
                    _statDivider(),
                    Expanded(child: _statCol('Pawing', p.pawingCount)),
                    _statDivider(),
                    Expanded(child: _statCol('Pawmate', p.pawmateCount)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 사진 없는 프로필 — 닉네임을 카드 중앙에 크게.
  Widget _noPhotoBackground(PublicProfileData p) {
    return ColoredBox(
      color: AppColors.primaryDark,
      child: Center(
        // 블러 구간(132px)을 피해 위쪽 영역의 가운데에 오도록 살짝 올린다.
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100, left: 24, right: 24),
          child: Text(
            p.nickname,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: AppColors.textOnPrimary,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaLine(PublicProfileData p) {
    final region = p.regionName;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _userTypeLabel(p.userType),
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

  Widget _statCol(String label, int value) => Column(
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

  Widget _actions(PublicProfileData p) {
    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: _toggleFollow,
            borderRadius: BorderRadius.circular(100),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _following ? AppColors.surface : AppColors.primaryDark,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: _following ? AppColors.border : AppColors.primaryDark,
                ),
              ),
              child: Text(
                _following ? 'Pawing 중' : 'Pawing',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _following
                      ? AppColors.textSecondary
                      : AppColors.textOnPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => openDirectChat(context, p.userId),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('채팅'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ── 반려동물: 포스터형 캐러셀 (내정보 펫중심과 동일 언어) ──
  // 타이틀은 WeatherCollapse 가 핀 고정하므로 내용만 만든다.

  Widget _petContent(PublicProfileData p) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: p.pets.isEmpty
          ? _emptyBox('등록된 반려동물이 없어요')
          : _PetPosterCarousel(
              pets: p.pets,
              openedPetId: _openedPetId,
              onTap: _openPet,
            ),
    );
  }

  // ── 받은 평가: 카테고리 태그 집계 ──

  Widget _reviewContent(PublicProfileData p) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: p.reviewTags.isEmpty
          ? _emptyBox('아직 받은 평가가 없어요')
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in p.reviewTags) _ReviewTagChip(tag: t),
                ],
              ),
            ),
    );
  }

  // ── 작성한 게시글: 대표사진 2열 그리드 ──

  Widget _postContent() {
    if (_posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: _emptyBox('작성한 게시글이 없어요'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // 상위 MediaQuery 패딩(상태바) 상속 방지 — 타이틀 밑 불필요한 공백 제거.
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: _posts.length,
        itemBuilder: (_, i) {
          final post = _posts[i];
          // 상세가 열린 타일은 빈자리로 — 축소가 겹침 없이 안착.
          return Opacity(
            key: _postKeys.putIfAbsent(post.id, GlobalKey.new),
            opacity: _openedPostId == post.id ? 0 : 1,
            child: PostPhotoTile(post: post, onTap: () => _openPost(post)),
          );
        },
      ),
    );
  }

  Widget _emptyBox(String msg) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.symmetric(vertical: 28),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Center(
      child: Text(
        msg,
        style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
      ),
    ),
  );
}

/// 작성한 게시글 그리드 타일 — 대표사진만 보여준다.
/// 사진 없는 게시글은 카테고리 색 배경 + 아이콘 위에 제목을 꽉 채워 표시
/// (타일 높이에 맞춰 줄바꿈, 넘치면 말줄임).
class PostPhotoTile extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;
  const PostPhotoTile({super.key, required this.post, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: post.imageUrl != null
            ? Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _textFallback(),
              )
            : _textFallback(),
      ),
    );
  }

  Widget _textFallback() {
    final color = categoryColor(post.category);
    const titleStyle = TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
      height: 1.35,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // 뿌연 배경 — 카테고리 색 블롭 아웃포커스(글마다 랜덤 패턴, 크림 베이스).
        BlobBackground(seed: post.id, color: color),
        // 제목 — 세로 가운데·좌측 정렬. 높이에 들어가는 줄 수만큼 줄바꿈하고,
        // 그래도 넘치면 중간에서 잘라 "..." 처리.
        Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, c) {
              final lineH =
                  (titleStyle.fontSize ?? 19) * (titleStyle.height ?? 1.35);
              final lines = (c.maxHeight / lineH).floor().clamp(1, 20);
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  post.title,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 받은 평가 태그 1개 — "친절해요 3" 형태의 칩.
class _ReviewTagChip extends StatelessWidget {
  final ReviewTag tag;
  const _ReviewTagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag.category,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${tag.count}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 타인 프로필의 반려동물 포스터 캐러셀 — 내정보 펫 히어로와 동일한 시각 언어.
class _PetPosterCarousel extends StatefulWidget {
  final List<MockPet> pets;
  final String? openedPetId; // 상세로 열린 펫 → 빈자리 처리
  final void Function(MockPet pet, Rect? rect) onTap;
  const _PetPosterCarousel({
    required this.pets,
    required this.onTap,
    this.openedPetId,
  });

  @override
  State<_PetPosterCarousel> createState() => _PetPosterCarouselState();
}

class _PetPosterCarouselState extends State<_PetPosterCarousel> {
  final _pc = PageController(viewportFraction: 0.9);
  int _page = 0;
  final _cardKeys = <String, GlobalKey>{};

  Rect? _cardRect(String id) {
    final ctx = _cardKeys[id]?.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pets = widget.pets;
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: PageView.builder(
            controller: _pc,
            padEnds: pets.length > 1,
            itemCount: pets.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final pet = pets[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Opacity(
                  key: _cardKeys.putIfAbsent(pet.id, GlobalKey.new),
                  opacity: widget.openedPetId == pet.id ? 0 : 1,
                  child: PetPosterCard(
                    pet: pet,
                    onTap: () => widget.onTap(pet, _cardRect(pet.id)),
                  ),
                ),
              );
            },
          ),
        ),
        if (pets.length > 1) ...[
          const SizedBox(height: 10),
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
                        ? AppColors.primaryDark
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 반려동물 포스터 카드(공개용) — 큰 사진 + 하단 그라데이션 위 이름/종·나이·성별,
/// 우상단 인증 배지. 내정보의 펫 히어로 카드와 같은 언어(역할 배지는 없음).
class PetPosterCard extends StatelessWidget {
  final MockPet pet;
  final VoidCallback? onTap;
  const PetPosterCard({super.key, required this.pet, this.onTap});

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
      if (pet.species.isNotEmpty) pet.species,
      if (age != null) age,
      if (genderKo != null) genderKo,
    ].join('  ·  ');

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (pet.imageUrl != null)
              Image.network(
                pet.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _PosterPlaceholder(),
              )
            else
              const _PosterPlaceholder(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
              ),
            ),
            if (pet.isIdentityVerified)
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified,
                        size: 13,
                        color: AppColors.primaryDark,
                      ),
                      SizedBox(width: 3),
                      Text(
                        '인증',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xF2FFFFFF),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.primarySoft,
    child: Center(
      child: Icon(Icons.pets, size: 64, color: AppColors.primaryDark),
    ),
  );
}
