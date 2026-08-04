import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/community.dart';
import '../models/pet_search.dart';
import '../motion/motion.dart';
import '../services/community/post_query_repository.dart';
import '../services/pet_repository.dart';
import '../theme/app_palette.dart';
import '../widgets/pet_trust_badge.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';
import 'user_profile_screen.dart';

/// 공개 반려동물 프로필 (read-only) — 검색에서 펫을 눌렀을 때 진입.
/// 포스터 히어로(사진·이름·기본정보) + 소개 + 보호자(공동보호자 포함) +
/// 이 아이가 태그된 게시글. [originRect] 가 있으면 검색 타일에서 펼쳐지고/
/// 당기면 그 자리로 축소된다(커뮤니티 게시글 상세와 동일한 전환 언어).
class PetProfileScreen extends StatefulWidget {
  final String petId;

  /// 검색 결과에서 받은 최소 정보 (로딩 동안 즉시 헤더 표시용, 선택).
  final PetHit? preview;

  /// 검색 타일에서 펼쳐지는 전환용. null 이면 일반 화면.
  final Rect? originRect;

  /// 축소 시 크로스페이드로 나타날 원본 타일(검색 결과와 동일 위젯).
  final WidgetBuilder? cardBuilder;

  /// 원본 타일의 모서리 곡률 — 축소 안착 시 곡률이 튀지 않도록 타일과 맞춘다.
  final double cardRadius;

  /// 이 화면으로 들어오기 직전에 보던 사용자 id(있으면). 그 보호자를 다시 열려 하면
  /// 새 화면을 쌓지 않고 pop 으로 되돌아간다(사용자→펫→사용자 무한 스택 방지).
  final String? fromUserId;

  const PetProfileScreen({
    super.key,
    required this.petId,
    this.preview,
    this.originRect,
    this.cardBuilder,
    this.cardRadius = 14,
    this.fromUserId,
  });

  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _PetProfileScreenState extends State<PetProfileScreen> {
  PetProfile? _pet;
  List<PetGuardian> _guardians = [];
  List<Post> _posts = [];
  bool _loading = true;
  bool _notFound = false;

  // CollapsibleView(당겨서 축소) 용 스크롤 컨트롤러.
  final _scroll = ScrollController();

  // 게시글 카드 → 상세 확장 전환용(커뮤니티와 동일 패턴).
  final _postKeys = <String, GlobalKey>{};
  String? _openedPostId;

  // 보호자 타일 GlobalKey + 상세로 열린 보호자 — 게시글 카드와 동일한 확장/축소.
  final _guardianKeys = <String, GlobalKey>{};
  String? _openedGuardianId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final results = await Future.wait([
        PetRepository.instance.fetchPublicPet(widget.petId),
        PetRepository.instance.fetchPublicGuardians(widget.petId),
        PostQueryRepository.instance
            .fetchPetPosts(widget.petId)
            .catchError((_) => const <Post>[]),
      ]);
      if (!mounted) return;
      final pet = results[0] as PetProfile?;
      setState(() {
        _pet = pet;
        _guardians = results[1] as List<PetGuardian>;
        _posts = results[2] as List<Post>;
        _notFound = pet == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (!silent) _notFound = true;
        _loading = false;
      });
    }
  }

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
      cardBuilder: rect == null ? null : (_) => PostCard(post: post),
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
    unawaited(_load(silent: true)); // 하트/댓글 변동 반영
  }

  Rect? _guardianRect(String userId) {
    final ctx = _guardianKeys[userId]?.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openGuardian(PetGuardian g) async {
    // 방금 거쳐온 보호자면 새로 쌓지 않고 되돌아간다(무한 왕복 방지).
    if (g.userId == widget.fromUserId) {
      // maybePop → CollapsibleView(PopScope)가 축소 애니메이션을 태운 뒤 팝.
      Navigator.of(context).maybePop();
      return;
    }
    final rect = _guardianRect(g.userId);
    final page = UserProfileScreen(
      userId: g.userId,
      previewNickname: g.nickname,
      fromPetId: widget.petId,
      originRect: rect,
      cardBuilder: rect == null ? null : (_) => _GuardianTile(guardian: g),
      forcePersonalFace: true, // 보호자 목록 = 개인 맥락(업체 연결 차단, 0025)
    );
    if (rect != null) setState(() => _openedGuardianId = g.userId);
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page)
          : CollapseRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    setState(() => _openedGuardianId = null);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    // 검색 타일에서 펼쳐지고/당기면 타일로 축소 — 게시글 상세와 동일 래퍼.
    // 상단바·뒤로가기 없이 콘텐츠가 최상단까지 차오르는 몰입형(당겨서 축소).
    return CollapsibleView(
      originRect: widget.originRect,
      card: widget.cardBuilder,
      cardRadius: widget.cardRadius,
      scrollController: _scroll,
      builder: (context, physics) => Scaffold(
        backgroundColor: context.colors.background,
        // 뒤로가기 버튼 없음 — 아래로 당겨 축소(CollapsibleView) 또는 시스템 뒤로.
        body: _body(physics, topInset),
      ),
    );
  }

  Widget _body(ScrollPhysics physics, double topInset) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notFound || _pet == null) {
      return Center(
        child: Text(
          '찾을 수 없는 반려동물이에요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      );
    }
    final pet = _pet!;
    var i = 0;
    return ListView(
      controller: _scroll,
      physics: physics,
      padding: EdgeInsets.only(top: topInset + 8, bottom: 40),
      children: [
        Entrance(index: i++, child: _hero(pet)),
        if (pet.bio != null && pet.bio!.isNotEmpty) ...[
          const SizedBox(height: 28),
          Entrance(index: i++, child: _bioSection(pet)),
        ],
        const SizedBox(height: 28),
        Entrance(index: i++, child: _guardianSection(pet)),
        const SizedBox(height: 28),
        Entrance(index: i++, child: _postSection()),
      ],
    );
  }

  // ── 포스터 히어로: 큰 사진 + 이름/기본정보 오버레이 + 인증·신뢰 배지 ──

  Widget _hero(PetProfile pet) {
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
      ?age,
      ?genderKo,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 360,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.colors.primarySoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.colors.border, width: 0.5),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (pet.imageUrl != null)
                  Image.network(
                    pet.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _HeroPlaceholder(),
                  )
                else
                  const _HeroPlaceholder(),
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
                  ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
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
                            fontSize: 14,
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
          if (pet.matchCount > 0) ...[
            const SizedBox(height: 10),
            PetTrustBadge(matchCount: pet.matchCount),
          ],
        ],
      ),
    );
  }

  Widget _bioSection(PetProfile pet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('소개'),
        const SizedBox(height: 10),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border, width: 0.5),
          ),
          child: Text(
            pet.bio!,
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textPrimary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── 보호자: 대표 + 공동보호자 목록 ──

  Widget _guardianSection(PetProfile pet) {
    // RPC 가 막히거나 비어 있으면 대표 보호자 한 명으로 폴백.
    final guardians = _guardians.isNotEmpty
        ? _guardians
        : [
            if (pet.ownerId.isNotEmpty)
              PetGuardian(
                userId: pet.ownerId,
                nickname: pet.ownerNickname,
                profileImageUrl: null,
                role: 'owner',
              ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('보호자', count: guardians.length),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (final g in guardians)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  // 상세가 열린 보호자는 빈자리로 — 축소가 겹침 없이 안착.
                  child: Opacity(
                    key: _guardianKeys.putIfAbsent(g.userId, GlobalKey.new),
                    opacity: _openedGuardianId == g.userId ? 0 : 1,
                    child: _GuardianTile(
                      guardian: g,
                      onTap: () => _openGuardian(g),
                    ),
                  ),
                ),
              if (guardians.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '보호자 정보를 불러오지 못했어요',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 이 아이가 태그된 게시글 ──

  Widget _postSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('함께한 게시글', count: _posts.length),
        const SizedBox(height: 10),
        if (_posts.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: context.colors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '아직 함께한 게시글이 없어요',
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
            child: Column(
              children: [
                for (final post in _posts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    // 상세가 열린 카드는 빈자리로 — 축소가 겹침 없이 안착.
                    child: Opacity(
                      key: _postKeys.putIfAbsent(post.id, GlobalKey.new),
                      opacity: _openedPostId == post.id ? 0 : 1,
                      child: PostCard(post: post, onTap: () => _openPost(post)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String label, {int? count}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: context.colors.textPrimary,
          ),
        ),
        if (count != null && count > 0) ...[
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ],
    ),
  );
}

/// 보호자 한 명 — 사용자 검색 타일(UserTile)과 동일한 프로스트 문법:
/// 프로필 사진 블러 배경 + 중앙 닉네임(역할은 위에 작은 캡션). 탭하면 그 자리에서
/// 사용자 프로필이 펼쳐지고 당기면 축소된다(게시글 상세와 동일).
class _GuardianTile extends StatelessWidget {
  final PetGuardian guardian;
  final VoidCallback? onTap;
  const _GuardianTile({required this.guardian, this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = guardian;
    final name = g.nickname.isEmpty ? '알 수 없음' : g.nickname;
    final photo = g.profileImageUrl;
    // 사진 없는 보호자는 프로필 상세 헤더와 동일한 primaryDark 배경으로(UserTile 과 동일).
    final hasPhoto = photo != null;
    return Pressable(
      onTap:
          onTap ??
          () => Navigator.push(
            context,
            AppPageRoute(
              builder: (_) => UserProfileScreen(
                userId: g.userId,
                previewNickname: g.nickname,
                forcePersonalFace: true, // 보호자 = 개인 맥락(0025)
              ),
            ),
          ),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hasPhoto ? null : context.colors.primaryDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            if (photo != null)
              Positioned.fill(
                // RepaintBoundary — Column 내 타일이라 블러 레이어를 격리(재래스터 방지).
                child: RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 18,
                      sigmaY: 18,
                      tileMode: ui.TileMode.clamp,
                    ),
                    child: Image.network(
                      photo,
                      fit: BoxFit.cover,
                      cacheWidth: 400, // 블러 배경 — 저해상 디코딩
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            if (photo != null)
              Positioned.fill(
                child: ColoredBox(color: context.colors.photoVeil),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    g.isOwner ? '대표 보호자' : '공동보호자',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: hasPhoto
                          ? context.colors.textTertiary
                          : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: hasPhoto
                          ? context.colors.textPrimary
                          : context.colors.textOnPrimary,
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

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.primarySoft,
    child: Center(
      child: Icon(Icons.pets, size: 80, color: context.colors.primaryDark),
    ),
  );
}
