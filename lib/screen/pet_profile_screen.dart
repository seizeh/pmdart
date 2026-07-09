import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../models/community.dart';
import '../models/pet_search.dart';
import '../services/community_repository.dart';
import '../services/pet_repository.dart';
import '../services/chat_launcher.dart';
import '../services/session.dart';
import '../widgets/pet_trust_badge.dart';
import '../widgets/post_card.dart';
import '../widgets/floating_back_button.dart';
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

  const PetProfileScreen({
    super.key,
    required this.petId,
    this.preview,
    this.originRect,
    this.cardBuilder,
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
        CommunityRepository.instance
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
    _load(silent: true); // 하트/댓글 변동 반영
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    // 검색 타일에서 펼쳐지고/당기면 타일로 축소 — 게시글 상세와 동일 래퍼.
    // 상단바 없이 콘텐츠가 최상단까지 차오르는 몰입형 + 떠 있는 뒤로가기.
    return CollapsibleView(
      originRect: widget.originRect,
      card: widget.cardBuilder,
      scrollController: _scroll,
      builder: (context, physics) => Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned.fill(child: _body(physics, topInset)),
            Positioned(
              top: topInset + 8,
              left: 16,
              child: const FloatingBackButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ScrollPhysics physics, double topInset) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notFound || _pet == null) {
      return const Center(
        child: Text('찾을 수 없는 반려동물이에요',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
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
      if (age != null) age,
      if (genderKo != null) genderKo,
      if (pet.isNeutered) '중성화 완료',
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
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified,
                              size: 13, color: AppColors.primaryDark),
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Text(
            pet.bio!,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary, height: 1.5),
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
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < guardians.length; i++) ...[
                if (i > 0)
                  const Divider(
                      height: 0.5, thickness: 0.5, color: AppColors.border),
                _GuardianRow(guardian: guardians[i]),
              ],
              if (guardians.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('보호자 정보를 불러오지 못했어요',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary)),
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
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text('아직 함께한 게시글이 없어요',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textTertiary)),
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
                      child: PostCard(
                        post: post,
                        onTap: () => _openPost(post),
                      ),
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if (count != null && count > 0) ...[
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

/// 보호자 한 명 — 아바타 + 닉네임 + 역할, 탭하면 그 사용자 프로필로.
class _GuardianRow extends StatelessWidget {
  final PetGuardian guardian;
  const _GuardianRow({required this.guardian});

  @override
  Widget build(BuildContext context) {
    final g = guardian;
    final isMe = g.userId == SessionManager.instance.user?.id;
    final name = g.nickname.isEmpty ? '알 수 없음' : g.nickname;
    return Pressable(
      onTap: () => Navigator.push(
        context,
        AppPageRoute(
          builder: (_) =>
              UserProfileScreen(userId: g.userId, previewNickname: g.nickname),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primarySoft,
              backgroundImage: g.profileImageUrl != null
                  ? NetworkImage(g.profileImageUrl!)
                  : null,
              child: g.profileImageUrl == null
                  ? Text(
                      name.characters.first,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.isOwner ? '대표 보호자' : '공동보호자',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (!isMe)
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline,
                    color: AppColors.primaryDark, size: 20),
                tooltip: '채팅',
                onPressed: () => openDirectChat(context, g.userId),
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
  Widget build(BuildContext context) => const ColoredBox(
        color: AppColors.primarySoft,
        child: Center(
          child: Icon(Icons.pets, size: 80, color: AppColors.primaryDark),
        ),
      );
}
