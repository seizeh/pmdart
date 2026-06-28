import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../models/community.dart';
import '../../services/facility_repository.dart';
import '../../services/community_repository.dart';
import '../../services/location_service.dart';
import '../../widgets/post_card.dart';
import '../post_detail_screen.dart';

// 게시글 행정동 클러스터 칩(시설과 별개) — 코드/라벨/색.
const _postsLayer = ('posts', '게시글', Color(0xFF26A69A));

/// 지도 탭 — 주변 반려동물 시설(공공데이터)을 네이버 지도에 표시 (0021).
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

// 지도에 표시할 시설 카테고리 — 코드/라벨/마커색.
// 앞 4종은 공공데이터(DB), pet_cafe 는 네이버 지역검색 실시간(DB 미적재).
const _facilityCats = <(String, String, Color)>[
  ('animal_hospital', '동물병원', Color(0xFFEF5350)),
  ('grooming', '미용', Color(0xFFAB47BC)),
  ('pet_hotel', '위탁·호텔', Color(0xFF42A5F5)),
  ('pet_sales', '분양', Color(0xFF66BB6A)),
  ('pet_cafe', '애견카페', Color(0xFFFF9800)),
];

Color _colorFor(String category) {
  for (final c in _facilityCats) {
    if (c.$1 == category) return c.$3;
  }
  return AppColors.primaryDark;
}

/// 마커 캡션 줄바꿈: 한 줄 최대 8글자.
/// 공백이 있으면 단어 단위로 끊되, 한 줄이 8자를 넘어도 단어는 안 자른다.
/// 공백이 없는 긴 이름은 8글자마다 강제로 끊는다.
String _wrapCaption(String name) {
  final s = name.trim();
  if (s.length <= 8) return s;
  const max = 8;
  if (s.contains(' ')) {
    final lines = <String>[];
    var cur = '';
    for (final w in s.split(RegExp(r'\s+'))) {
      if (cur.isEmpty) {
        cur = w;
      } else if (cur.length + 1 + w.length <= max) {
        cur = '$cur $w';
      } else {
        lines.add(cur);
        cur = w;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines.join('\n');
  }
  final lines = <String>[];
  for (var i = 0; i < s.length; i += max) {
    final end = (i + max < s.length) ? i + max : s.length;
    lines.add(s.substring(i, end));
  }
  return lines.join('\n');
}

class _MapTabState extends State<MapTab> {
  NaverMapController? _controller;
  final _searchController = TextEditingController();
  bool _locating = false;
  bool _loadingFac = false;

  // 선택된 카테고리(기본 전체). 마커 id → Facility(탭 시 바텀시트용).
  final Set<String> _selected = {for (final c in _facilityCats) c.$1};
  final Map<String, Facility> _byMarkerId = {};
  final Map<String, PostCluster> _clusterByMarkerId = {}; // 게시글 클러스터 마커
  NLatLng? _loadedCenter; // 마지막 조회 중심(디바운스 기준)

  // 네이버 지도 커스텀 스타일(지도 스타일 에디터에서 발급한 ID).
  static const _customStyleId = '430d08d6-8afd-4661-9ffe-bcbf5c4351f4';
  static const _defaultZoom = 14.0;
  static const _seoul = NLatLng(37.5666, 126.9784);
  static const _initialPosition =
      NCameraPosition(target: _seoul, zoom: _defaultZoom);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 반경 5km 시설 조회 → 마커 갱신.
  Future<void> _loadFacilities(NLatLng center) async {
    final c = _controller;
    if (c == null) return;
    setState(() => _loadingFac = true);
    try {
      // 공공데이터(DB) 카테고리 + 애견카페(실시간) 분리 조회 후 합친다.
      final dbCats =
          _selected.where((cat) => cat != 'pet_cafe').toList();
      final rows = <Facility>[
        if (dbCats.isNotEmpty)
          ...await FacilityRepository.instance.nearby(
            lat: center.latitude,
            lng: center.longitude,
            radiusM: 5000,
            categories: dbCats,
          ),
        if (_selected.contains('pet_cafe'))
          ...await FacilityRepository.instance.searchPetCafes(
            lat: center.latitude,
            lng: center.longitude,
          ),
      ];
      // 게시글 행정동 클러스터(현재 뷰포트 bbox 기준) — 별도 레이어.
      final clusters = _selected.contains('posts')
          ? await _loadClusters(c)
          : const <PostCluster>[];

      await c.clearOverlays(type: NOverlayType.marker);
      _byMarkerId.clear();
      _clusterByMarkerId.clear();
      final markers = <NAddableOverlay>{};
      for (final f in rows) {
        final id = 'fac_${f.id}';
        final m = NMarker(id: id, position: NLatLng(f.lat, f.lng))
          ..setIconTintColor(_colorFor(f.category))
          ..setIsHideCollidedMarkers(true)
          ..setCaption(NOverlayCaption(
            text: _wrapCaption(f.name),
            textSize: 11,
            color: AppColors.textPrimary,
            haloColor: Colors.white,
          ))
          ..setIsHideCollidedCaptions(true)
          ..setOnTapListener((_) => _showFacilitySheet(f));
        _byMarkerId[id] = f;
        markers.add(m);
      }
      for (final cl in clusters) {
        final id = 'cluster_${cl.regionCode}';
        final m = NMarker(id: id, position: NLatLng(cl.lat, cl.lng))
          ..setIconTintColor(_postsLayer.$3)
          ..setCaption(NOverlayCaption(
            text: '게시글 ${cl.count}',
            color: _postsLayer.$3,
            haloColor: Colors.white,
          ))
          ..setOnTapListener((_) => _showRegionPosts(cl));
        _clusterByMarkerId[id] = cl;
        markers.add(m);
      }
      if (markers.isNotEmpty) await c.addOverlayAll(markers);
      _loadedCenter = center;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주변 시설을 불러오지 못했어요')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingFac = false);
    }
  }

  /// 현재 뷰포트(bbox) 안의 게시글 행정동 클러스터 조회.
  Future<List<PostCluster>> _loadClusters(NaverMapController c) async {
    try {
      final b = await c.getContentBounds();
      return await CommunityRepository.instance.postsByRegion(
        minLng: b.southWest.longitude,
        minLat: b.southWest.latitude,
        maxLng: b.northEast.longitude,
        maxLat: b.northEast.latitude,
      );
    } catch (_) {
      return const [];
    }
  }

  /// 클러스터 탭 → 그 행정동 게시글 목록 시트.
  void _showRegionPosts(PostCluster cl) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.forum_outlined, size: 18, color: _postsLayer.$3),
                  const SizedBox(width: 8),
                  Text('이 동네 게시글 ${cl.count}개',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Post>>(
                future:
                    CommunityRepository.instance.fetchPostsByIds(cl.postIds),
                builder: (fctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4));
                  }
                  final posts = snap.data ?? const <Post>[];
                  if (posts.isEmpty) {
                    return const Center(
                        child: Text('게시글을 불러오지 못했어요',
                            style: TextStyle(color: AppColors.textTertiary)));
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: posts.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: PostCard(
                        post: posts[i],
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PostDetailScreen(post: posts[i]),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 지도 준비 → 현재 위치로 이동 + 시설 조회. 위치 실패 시 서울 기준.
  Future<void> _initLoad() async {
    final c = _controller;
    if (c == null) return;
    final loc = await LocationService.instance.getCurrentPosition();
    if (loc.status == LocationStatus.ok && loc.position != null) {
      final p = NLatLng(loc.position!.latitude, loc.position!.longitude);
      await c.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: p, zoom: _defaultZoom),
      );
      await _loadFacilities(p);
    } else {
      await _loadFacilities(_seoul);
    }
  }

  /// 내 위치로 이동 + 그 지점 시설 재조회.
  Future<void> _goToMyLocation() async {
    final c = _controller;
    if (c == null || _locating) return;
    setState(() => _locating = true);
    c.setLocationTrackingMode(NLocationTrackingMode.follow);
    NLatLng? pos;
    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      try {
        final p = await c.getLocationOverlay().getPosition();
        if (p.latitude != 0 || p.longitude != 0) {
          pos = p;
          break;
        }
      } catch (_) {}
    }
    if (pos != null) {
      await c.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: pos, zoom: _defaultZoom)
          ..setAnimation(
              animation: NCameraAnimation.easing,
              duration: const Duration(milliseconds: 350)),
      );
      await _loadFacilities(pos);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져올 수 없어요. 위치 권한을 확인해주세요.')),
      );
    }
    if (mounted) setState(() => _locating = false);
  }

  /// 지도 이동이 멈췄을 때, 중심이 1km 이상 벗어났으면 재조회(디바운스).
  Future<void> _onCameraIdle() async {
    // 지도를 움직였다는 건 입력 중이 아니란 뜻 → 키보드 내리기.
    FocusManager.instance.primaryFocus?.unfocus();
    final c = _controller;
    if (c == null || _loadedCenter == null || _loadingFac) return;
    final cam = await c.getCameraPosition();
    final moved = Geolocator.distanceBetween(
      _loadedCenter!.latitude, _loadedCenter!.longitude,
      cam.target.latitude, cam.target.longitude,
    );
    if (moved > 1000) await _loadFacilities(cam.target);
  }

  void _toggleCategory(String code) {
    setState(() {
      if (!_selected.add(code)) _selected.remove(code);
    });
    if (_loadedCenter != null) _loadFacilities(_loadedCenter!);
  }

  /// 네이버 지도로 링크 아웃 — 영업시간 등 상세는 거기서 확인.
  /// 상호 + 자치구만으로 검색한다. 공공데이터 주소는 번지가 ***로 마스킹돼 있어
  /// 전체 주소로 검색하면 오히려 결과가 안 나온다.
  Future<void> _openInNaverMap(Facility f) async {
    final addr = f.address ?? '';
    final gu = RegExp(r'\S+구').firstMatch(addr)?.group(0) ??
        RegExp(r'\S+[시군]').firstMatch(addr)?.group(0) ??
        '';
    final query =
        [f.name, gu].where((s) => s.isNotEmpty).join(' ').trim();
    final uri = Uri.parse(
        'https://map.naver.com/p/search/${Uri.encodeComponent(query)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네이버 지도를 열 수 없어요')),
      );
    }
  }

  void _showFacilitySheet(Facility f) {
    final color = _colorFor(f.category);
    final dist = f.distanceM < 1000
        ? '${f.distanceM.round()}m'
        : '${(f.distanceM / 1000).toStringAsFixed(1)}km';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(kFacilityLabels[f.category] ?? f.category,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ),
                  const Spacer(),
                  Text(dist,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
              const SizedBox(height: 12),
              Text(f.name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              if (f.address != null && f.address!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _row(Icons.place_outlined, f.address!),
              ],
              if (f.phone != null && f.phone!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _row(Icons.call_outlined, f.phone!),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openInNaverMap(f),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('네이버 지도에서 보기 (영업시간 등)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          ),
        ],
      );

  /// 시설명 검색 → 가장 가까운 결과로 카메라 이동 + 상세 시트.
  Future<void> _onSearchSubmitted(String query) async {
    final q = query.trim();
    final c = _controller;
    if (q.isEmpty || c == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final center = _loadedCenter;
    List<Facility> results;
    try {
      results = await FacilityRepository.instance.searchByName(
        q,
        lat: center?.latitude,
        lng: center?.longitude,
      );
    } catch (_) {
      results = const [];
    }
    if (!mounted) return;
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$q" 검색 결과가 없어요')),
      );
      return;
    }
    final top = results.first;
    await c.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(top.lat, top.lng),
        zoom: 16,
      )..setAnimation(
          animation: NCameraAnimation.easing,
          duration: const Duration(milliseconds: 400),
        ),
    );
    // 이동하면 onCameraIdle 가 주변 마커를 다시 로드한다. 매칭 시설 상세를 바로 보여준다.
    if (mounted) _showFacilitySheet(top);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          ClipRect(
            child: NaverMap(
              options: const NaverMapViewOptions(
                initialCameraPosition: _initialPosition,
                customStyleId: _customStyleId,
                locationButtonEnable: false,
                consumeSymbolTapEvents: false,
              ),
              onMapReady: (controller) {
                _controller = controller;
                _initLoad();
              },
              onCameraIdle: _onCameraIdle,
              // 지도는 네이티브 뷰라 루트 GestureDetector 가 탭을 못 받는다.
              // 지도를 탭하면 검색창 포커스를 직접 해제(키보드 닫기).
              onMapTapped: (_, _) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onCustomStyleLoadFailed: (e) {
                debugPrint('커스텀 지도 스타일 로드 실패: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('지도 스타일을 불러오지 못했어요')),
                  );
                }
              },
            ),
          ),

          // 상단: 검색창 + 카테고리 필터칩
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    _SearchField(
                      controller: _searchController,
                      onSubmitted: _onSearchSubmitted,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final c in _facilityCats)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _CatChip(
                                label: c.$2,
                                color: c.$3,
                                selected: _selected.contains(c.$1),
                                onTap: () => _toggleCategory(c.$1),
                              ),
                            ),
                          // 게시글 클러스터 레이어(시설과 별개)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _CatChip(
                              label: _postsLayer.$2,
                              color: _postsLayer.$3,
                              selected: _selected.contains(_postsLayer.$1),
                              onTap: () => _toggleCategory(_postsLayer.$1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_loadingFac)
            const Positioned(
              top: 0, left: 0, right: 0, bottom: 0,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4)),
                  ),
                ),
              ),
            ),

          Positioned(
            right: 16,
            bottom: 24,
            child: _MyLocationButton(loading: _locating, onTap: _goToMyLocation),
          ),
        ],
      ),
    );
  }
}

/// 카테고리 필터 칩.
class _CatChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip(
      {required this.label,
      required this.color,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: selected ? color : AppColors.border, width: 0.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.white : color),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  const _SearchField({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.textTertiary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '시설·장소 검색...',
                hintStyle:
                    TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyLocationButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _MyLocationButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(AppColors.primaryDark),
                    ),
                  )
                : const Icon(Icons.my_location,
                    color: AppColors.primaryDark, size: 24),
          ),
        ),
      ),
    );
  }
}
