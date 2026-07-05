import 'dart:async';
import '../../motion/motion.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/social.dart';
import '../../models/pet_search.dart';
import '../../services/social_repository.dart';
import '../../widgets/user_tile.dart';
import '../../widgets/gradient_header.dart';
import '../pet_profile_screen.dart';

/// 사용자 검색 탭 — 닉네임 또는 반려동물 이름으로 검색(입력 즉시).
/// 보호자 결과는 팔로우/채팅, 반려동물 결과는 펫 프로필로 이동.
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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(topInset + 126)),
          GradientHeader(
            topInset: topInset,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '사용자 검색',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (v) {
                      final q = v.trim();
                      if (q.isNotEmpty) _runSearch(q);
                    },
                    decoration: InputDecoration(
                      hintText: '닉네임이나 반려동물의 이름으로 검색',
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.textSecondary,
                      ),
                      suffixIcon: _ctrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.textTertiary,
                              ),
                              onPressed: _clear,
                            ),
                    ),
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
          for (final pet in _petResults) PetSearchTile(pet: pet),
        ],
        if (_results.isNotEmpty) ...[
          _sectionHeader('보호자'),
          for (final c in _results) UserTile(connection: c),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
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
            const Icon(
              Icons.person_search_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
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
  const PetSearchTile({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (pet.species.isNotEmpty) pet.species,
      if (pet.ownerNickname.isNotEmpty) '보호자 ${pet.ownerNickname}',
    ].join('  ·  ');

    return InkWell(
      onTap: () => Navigator.push(
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
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
                image: pet.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(pet.imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: pet.imageUrl == null
                  ? const Icon(
                      Icons.pets,
                      color: AppColors.primaryDark,
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
