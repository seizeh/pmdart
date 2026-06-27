import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_colors.dart';
import '../../services/facility_repository.dart';
import '../../services/location_service.dart';

/// 지도 탭 — 주변 반려동물 시설(공공데이터)을 네이버 지도에 표시 (0021).
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

// 지도에 표시할 시설 카테고리(공공데이터 4종) — 코드/라벨/마커색.
const _facilityCats = <(String, String, Color)>[
  ('animal_hospital', '동물병원', Color(0xFFEF5350)),
  ('grooming', '미용', Color(0xFFAB47BC)),
  ('pet_hotel', '위탁·호텔', Color(0xFF42A5F5)),
  ('pet_sales', '분양', Color(0xFF66BB6A)),
];

Color _colorFor(String category) {
  for (final c in _facilityCats) {
    if (c.$1 == category) return c.$3;
  }
  return AppColors.primaryDark;
}

class _MapTabState extends State<MapTab> {
  NaverMapController? _controller;
  final _searchController = TextEditingController();
  bool _locating = false;
  bool _loadingFac = false;

  // 선택된 카테고리(기본 전체). 마커 id → Facility(탭 시 바텀시트용).
  final Set<String> _selected = {for (final c in _facilityCats) c.$1};
  final Map<String, Facility> _byMarkerId = {};
  NLatLng? _loadedCenter; // 마지막 조회 중심(디바운스 기준)

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
      final rows = await FacilityRepository.instance.nearby(
        lat: center.latitude,
        lng: center.longitude,
        radiusM: 5000,
        categories: _selected.toList(),
      );
      await c.clearOverlays(type: NOverlayType.marker);
      _byMarkerId.clear();
      final markers = <NAddableOverlay>{};
      for (final f in rows) {
        final id = 'fac_${f.id}';
        final m = NMarker(id: id, position: NLatLng(f.lat, f.lng))
          ..setIconTintColor(_colorFor(f.category))
          ..setIsHideCollidedMarkers(true)
          ..setOnTapListener((_) => _showFacilitySheet(f));
        _byMarkerId[id] = f;
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

  void _onSearchSubmitted(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$q" 검색 기능은 곧 연결됩니다.')),
    );
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
                locationButtonEnable: false,
                consumeSymbolTapEvents: false,
              ),
              onMapReady: (controller) {
                _controller = controller;
                _initLoad();
              },
              onCameraIdle: _onCameraIdle,
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
