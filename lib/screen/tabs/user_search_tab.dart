import 'dart:async';
import '../../motion/motion.dart';
import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../models/social.dart';
import '../../models/pet_search.dart';
import '../../services/social_repository.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/user_tile.dart';
import '../../widgets/gradient_header.dart';
import '../pet_profile_screen.dart';
import '../user_profile_screen.dart';

/// 사용자 검색 탭 — 닉네임 또는 반려동물 이름으로 검색(입력 즉시).
/// 결과 타일을 누르면 그 자리에서 프로필이 펼쳐지고, 당기면 타일로 축소된다
/// (커뮤니티 게시글 상세와 동일한 전환).
class UserSearchTab extends StatefulWidget {
  const UserSearchTab({super.key});

  @override
  State<UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends State<UserSearchTab> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _reqId = 0; // 응답 순서 꼬임 방지

  List<Connection> _results = [];
  List<PetHit> _petResults = [];
  bool _loading = false;
  bool _searched = false;

  // 타일별 GlobalKey — 탭 시 타일의 화면 위치를 캡처해 프로필을 그 자리에서
  // 펼치고, 당기면 그 자리로 축소시키는 CollapseRoute 에 넘긴다(커뮤니티와 동일).
  final _tileKeys = <String, GlobalKey>{};

  // 프로필로 열려 있는 타일 id — 열린 동안 투명(빈자리)으로 두어
  // 축소 애니메이션이 실제 타일과 겹치지 않고 깔끔히 안착하게 한다.
  String? _openedTileId;

  Rect? _tileRect(String id) {
    final ctx = _tileKeys[id]?.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// 타일 자리에서 [page] 를 펼친다. rect 를 못 구하면 표준 라우트로 폴백.
  Future<void> _openFromTile(
    String tileId,
    Widget Function(Rect? rect) page,
  ) async {
    final rect = _tileRect(tileId);
    if (rect != null) setState(() => _openedTileId = tileId);
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page(null))
          : CollapseRoute<void>(builder: (_) => page(rect)),
    );
    if (mounted) setState(() => _openedTileId = null);
  }

  void _openUser(Connection c) {
    final tileId = 'user:${c.userId}';
    _openFromTile(
      tileId,
      (rect) => UserProfileScreen(
        userId: c.userId,
        // 업체 결과는 미리보기(로딩 전 표시)도 상호로 — 닉네임 노출 방지
        previewNickname: c.businessName ?? c.nickname,
        originRect: rect,
        cardBuilder: rect == null ? null : (_) => UserTile(connection: c),
      ),
    );
  }

  void _openPet(PetHit pet) {
    final tileId = 'pet:${pet.id}';
    _openFromTile(
      tileId,
      (rect) => PetProfileScreen(
        petId: pet.id,
        preview: pet,
        originRect: rect,
        cardBuilder: rect == null ? null : (_) => PetSearchTile(pet: pet),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _petResults = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final myReq = ++_reqId;
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final repo = SocialRepository.instance;
      final results = await Future.wait([
        repo.searchUsers(q),
        repo.searchPets(q),
      ]);
      if (!mounted || myReq != _reqId) return; // 더 최신 검색이 있으면 무시
      setState(() {
        _results = results[0] as List<Connection>;
        _petResults = results[1] as List<PetHit>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || myReq != _reqId) return;
      setState(() {
        _results = [];
        _petResults = [];
        _loading = false;
      });
    }
  }

  void _clear() {
    _ctrl.clear();
    _debounce?.cancel();
    setState(() {
      _results = [];
      _petResults = [];
      _searched = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    // 메인(커뮤니티)과 동일하게: 결과 리스트가 상단 그라데이션 헤더 아래로 스크롤되며 페이드.
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          // 헤더가 상태바 아래로 8 떠 있으므로 그만큼 리스트 시작점도 내린다.
          Positioned.fill(child: _buildBody(topInset + 134)),
          GradientHeader(
            topInset: topInset,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '사용자 검색',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: context.colors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppSearchField(
                    controller: _ctrl,
                    autofocus: true,
                    hintText: '닉네임이나 반려동물의 이름으로 검색',
                    onChanged: _onChanged,
                    onSubmitted: (v) {
                      final q = v.trim();
                      if (q.isNotEmpty) _runSearch(q);
                    },
                    onClear: _clear,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double topPad) {
    if (_loading) {
      return Padding(
        padding: EdgeInsets.only(top: topPad),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_searched) {
      return _hint('닉네임이나 반려동물 이름을 입력해\n보호자를 찾아보세요', topPad);
    }
    if (_results.isEmpty && _petResults.isEmpty) {
      return _hint('검색 결과가 없어요', topPad);
    }
    return ListView(
      padding: EdgeInsets.only(top: topPad, left: 20, right: 20, bottom: 20),
      children: [
        if (_petResults.isNotEmpty) ...[
          _sectionHeader('반려동물'),
          for (final pet in _petResults)
            // 프로필이 열린 타일은 빈자리로 — 축소가 겹침 없이 안착.
            // 타일 간격은 채팅 목록과 동일하게 10.
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                key: _tileKeys.putIfAbsent('pet:${pet.id}', GlobalKey.new),
                opacity: _openedTileId == 'pet:${pet.id}' ? 0 : 1,
                child: PetSearchTile(pet: pet, onTap: () => _openPet(pet)),
              ),
            ),
        ],
        if (_results.isNotEmpty) ...[
          _sectionHeader('보호자'),
          for (final c in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                key: _tileKeys.putIfAbsent('user:${c.userId}', GlobalKey.new),
                opacity: _openedTileId == 'user:${c.userId}' ? 0 : 1,
                child: UserTile(connection: c, onTap: () => _openUser(c)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.colors.textSecondary,
      ),
    ),
  );

  Widget _hint(String msg, double topPad) {
    return Padding(
      padding: EdgeInsets.only(top: topPad),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_search_outlined,
              size: 56,
              color: context.colors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 검색 결과의 반려동물 한 마리 — 누르면 펫 프로필로 이동.
class PetSearchTile extends StatelessWidget {
  final PetHit pet;

  /// 탭 동작 재정의(선택) — 검색 탭이 타일 자리에서 펼쳐지는 전환을 걸 때 사용.
  final VoidCallback? onTap;

  const PetSearchTile({super.key, required this.pet, this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (pet.species.isNotEmpty) pet.species,
      if (pet.ownerNickname.isNotEmpty) '보호자 ${pet.ownerNickname}',
    ].join('  ·  ');

    return InkWell(
      onTap:
          onTap ??
          () => Navigator.push(
            context,
            AppPageRoute(
              builder: (_) => PetProfileScreen(petId: pet.id, preview: pet),
            ),
          ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.colors.primarySoft,
                borderRadius: BorderRadius.circular(14),
                image: pet.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(pet.imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: pet.imageUrl == null
                  ? Icon(
                      Icons.pets,
                      color: context.colors.primaryDark,
                      size: 22,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.colors.textTertiary),
          ],
        ),
      ),
    );
  }
}
