import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/pet_search.dart';
import '../../models/social.dart';
import '../../motion/motion.dart';
import '../../services/facility_repository.dart';
import '../../services/social_repository.dart';
import '../../theme/app_palette.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/facility_sheet.dart';
import '../../widgets/gradient_header.dart';
import '../../widgets/map_bottom_sheet.dart';
import '../../widgets/profile_square_card.dart';
import '../pet_profile_screen.dart';
import '../user_profile_screen.dart';

/// 사용자 검색 탭 — 닉네임 또는 반려동물 이름으로 검색(입력 즉시).
/// 결과 타일을 누르면 그 자리에서 프로필이 펼쳐지고, 당기면 타일로 축소된다
/// (커뮤니티 게시글 상세와 동일한 전환).
class UserSearchTab extends StatefulWidget {
  /// 아래로 스크롤 시 함께 숨길 하단 크롬(네비 바) — 커뮤니티·내정보와 동일 신호.
  final ValueNotifier<bool>? chromeVisible;
  const UserSearchTab({super.key, this.chromeVisible});

  @override
  State<UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends State<UserSearchTab>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();

  // 상단 헤더 + 하단 네비 바 숨김/복귀 — 규칙은 lib/motion/scroll_chrome.dart.
  //
  // 여기 헤더는 제목 + 검색창이라 다른 탭보다 높다(topPad 134). 그래서 되돌아오는
  // 기준선도 헤더 높이에 맞춰 넉넉히 잡는다 — 64 로 두면 검색창이 반쯤 걸친
  // 어중간한 위치에서 숨었다 나타났다 한다.
  late final _chrome = ScrollChrome(
    vsync: this,
    chromeVisible: widget.chromeVisible,
    revealBelow: 100,
  );
  Timer? _debounce;
  int _reqId = 0; // 응답 순서 꼬임 방지

  List<Connection> _results = [];
  List<PetHit> _petResults = [];
  // 매장(공공데이터 시설) 결과 — 업체 인증 전이라 프로필이 없는 곳도 여기서 찾는다.
  List<Facility> _facilityResults = [];
  bool _loading = false;
  bool _searched = false;

  // 검색 전 기본 화면에 보여줄 승인 업체 목록(진입 시 1회 로드).
  List<Connection> _businesses = [];

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

  // 같은 사용자의 개인/업체 얼굴이 결과에 동시에 나올 수 있다 — 타일 id 에
  // 얼굴을 포함해야 GlobalKey 가 충돌하지 않는다(충돌 시 한 행이 사라짐).
  String _userTileId(Connection c) =>
      'user:${c.userId}:${c.isBusiness ? 'biz' : 'personal'}';

  void _openUser(Connection c) {
    final tileId = _userTileId(c);
    _openFromTile(
      tileId,
      (rect) => UserProfileScreen(
        userId: c.userId,
        // 업체 결과는 미리보기(로딩 전 표시)도 상호로 — 닉네임 노출 방지
        previewNickname: c.businessName ?? c.nickname,
        // 상호로 찾은 결과만 업체 얼굴 — 닉네임 결과는 개인 얼굴 고정(연결 차단)
        forcePersonalFace: c.businessName == null,
        originRect: rect,
        // 축소 안착 시 크로스페이드할 카드 — 그리드의 둥근 정사각형과 동일.
        cardRadius: ProfileSquareCard.radius,
        cardBuilder: rect == null
            ? null
            : (_) => ProfileSquareCard(connection: c),
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
        cardRadius: ProfileSquareCard.radius,
        cardBuilder: rect == null ? null : (_) => PetSquareCard(pet: pet),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  Future<void> _loadBusinesses() async {
    try {
      final list = await SocialRepository.instance.listBusinesses();
      if (!mounted) return;
      setState(() => _businesses = list);
    } catch (_) {
      // 실패해도 기본 화면은 안내 문구로 폴백 — 검색 기능엔 영향 없음.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _chrome.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _petResults = [];
        _facilityResults = [];
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
      // 매장 검색은 좌표 없이(이름만) — 웹은 위치를 수집하지 않고, 비로그인도
      // 상호로 찾아 후기까지 갈 수 있어야 한다.
      final results = await Future.wait([
        repo.searchUsers(q),
        repo.searchPets(q),
        FacilityRepository.instance.searchByName(q),
      ]);
      if (!mounted || myReq != _reqId) return; // 더 최신 검색이 있으면 무시
      setState(() {
        _results = results[0] as List<Connection>;
        _petResults = results[1] as List<PetHit>;
        _facilityResults = results[2] as List<Facility>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || myReq != _reqId) return;
      setState(() {
        _results = [];
        _petResults = [];
        _facilityResults = [];
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
      _facilityResults = [];
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
          Positioned.fill(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _chrome.onUserScroll,
              child: _buildBody(topInset + 134),
            ),
          ),
          // 헤더 — 아래로 스크롤 시 위로 밀려 숨고, 위로 올리면 스프링 복귀
          // (하단 네비 바와 같은 신호로 동기화).
          AnimatedBuilder(
            animation: _chrome,
            builder: (context, child) => GradientHeader(
              topInset: topInset,
              shift: _chrome.hidden * (topInset + 150),
              child: child!,
            ),
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
                    hintText: '매장·닉네임·반려동물 이름으로 검색',
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
      // 검색 전 기본 화면 — 승인 업체 프로필 목록(없으면 안내 문구).
      if (_businesses.isEmpty) {
        return _hint('닉네임이나 반려동물 이름을 입력해\n보호자를 찾아보세요', topPad);
      }
      return ListView(
        padding: EdgeInsets.only(top: topPad, left: 20, right: 20, bottom: 20),
        children: [
          _sectionHeader('인증 업체'),
          _grid([for (final c in _businesses) _userCard(c)]),
        ],
      );
    }
    if (_results.isEmpty && _petResults.isEmpty && _facilityResults.isEmpty) {
      return _hint('검색 결과가 없어요', topPad);
    }
    return ListView(
      padding: EdgeInsets.only(top: topPad, left: 20, right: 20, bottom: 20),
      children: [
        // 사람·반려동물이 먼저, 매장은 맨 아래 — 사용자 검색 탭의 주 대상은
        // 보호자다(매장 우선이던 종전 배치를 뒤집음).
        if (_results.isNotEmpty) ...[
          _sectionHeader('보호자'),
          _grid([for (final c in _results) _userCard(c)]),
        ],
        if (_petResults.isNotEmpty) ...[
          _sectionHeader('반려동물'),
          _grid([
            for (final pet in _petResults)
              // 프로필이 열린 카드는 빈자리로 — 축소가 겹침 없이 안착.
              Opacity(
                key: _tileKeys.putIfAbsent('pet:${pet.id}', GlobalKey.new),
                opacity: _openedTileId == 'pet:${pet.id}' ? 0 : 1,
                child: PetSquareCard(pet: pet, onTap: () => _openPet(pet)),
              ),
          ]),
        ],
        if (_facilityResults.isNotEmpty) ...[
          _sectionHeader('매장'),
          _grid([for (final f in _facilityResults) _facilityCard(f)]),
        ],
      ],
    );
  }

  /// 둥근 정사각형 카드 2열 그리드 — 바깥 ListView 안에서 스크롤 없이 펼친다.
  Widget _grid(List<Widget> cells) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: 1,
    padding: const EdgeInsets.only(bottom: 10),
    children: cells,
  );

  // 프로필이 열린 카드는 빈자리로 — 축소가 겹침 없이 안착.
  Widget _userCard(Connection c) => Opacity(
    key: _tileKeys.putIfAbsent(_userTileId(c), GlobalKey.new),
    opacity: _openedTileId == _userTileId(c) ? 0 : 1,
    child: ProfileSquareCard(connection: c, onTap: () => _openUser(c)),
  );

  /// 매장 카드 — 누르면 지도 탭과 동일한 시설 상세 시트(정보 + 후기 목록 +
  /// 후기 쓰기)를 띄운다. 인증 업체(프로필 상세)와 동선 문법을 통일 —
  /// "카드 탭 = 먼저 보기, 작성은 그 안에서".
  Widget _facilityCard(Facility f) =>
      FacilitySquareCard(facility: f, onTap: () => _openFacility(f));

  /// 지도 탭의 카테고리 마커색과 동일(수동 동기화) — 시설 상세 헤더 색.
  Color _facilityColor(String category) => switch (category) {
    'animal_hospital' => const Color(0xFFEF5350),
    'grooming' => const Color(0xFFAB47BC),
    'pet_hotel' => const Color(0xFF42A5F5),
    'pet_sales' => const Color(0xFF66BB6A),
    'pet_cafe' => const Color(0xFFFF9800),
    _ => const Color(0xFF5A4E3A),
  };

  void _openFacility(Facility f) {
    // MapBottomSheet 는 스크림·슬라이드·드래그 닫기를 자급자족한다 — 투명
    // 라우트로 띄우기만 하면 지도 탭과 같은 시트가 된다(전환은 시트가 담당).
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (ctx, _, _) => MapBottomSheet(
          onClose: () => Navigator.of(ctx).pop(),
          child: FacilityDetailContent(
            facility: f,
            color: _facilityColor(f.category),
            label: kFacilityLabels[f.category] ?? f.category,
          ),
        ),
      ),
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
