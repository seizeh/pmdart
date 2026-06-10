import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import '../../theme/app_colors.dart';

/// 지도 탭 — 주변 산책 메이트·업체를 네이버 지도로 표시.
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  NaverMapController? _controller;
  final _searchController = TextEditingController();
  bool _locating = false;

  // 기본 카메라 위치·줌 (서울시청). 위치 버튼을 누르면 이 줌으로 복귀.
  static const _defaultZoom = 14.0;
  static const _initialPosition = NCameraPosition(
    target: NLatLng(37.5666, 126.9784),
    zoom: _defaultZoom,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 내 위치로 이동 + 기본 줌으로 복귀.
  Future<void> _goToMyLocation() async {
    final c = _controller;
    if (c == null || _locating) return;
    setState(() => _locating = true);

    // 추적 모드 활성화 → 권한 요청·현재 위치 오버레이 표시 (기본 트래커가 자동 처리).
    c.setLocationTrackingMode(NLocationTrackingMode.follow);

    // 위치 픽스를 기다렸다가 현재 위치로 기본 줌 적용.
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
      } catch (_) {/* 아직 위치 없음 */}
    }

    if (pos != null) {
      await c.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: pos, zoom: _defaultZoom)
          ..setAnimation(
            animation: NCameraAnimation.easing,
            duration: const Duration(milliseconds: 350),
          ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져올 수 없어요. 위치 권한을 확인해주세요.')),
      );
    }

    if (mounted) setState(() => _locating = false);
  }

  void _onSearchSubmitted(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    // TODO: 네이버 지역 검색/지오코딩 API 연동 후 결과로 카메라 이동.
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
          NaverMap(
            options: const NaverMapViewOptions(
              initialCameraPosition: _initialPosition,
              locationButtonEnable: false, // 기본 버튼 끄고 커스텀 버튼 사용
              consumeSymbolTapEvents: false,
            ),
            onMapReady: (controller) {
              _controller = controller;
              debugPrint('네이버 지도 준비 완료');
            },
          ),

          // 상단 시설물 검색창
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _SearchField(
                  controller: _searchController,
                  onSubmitted: _onSearchSubmitted,
                ),
              ),
            ),
          ),

          // 우하단 내 위치 버튼
          Positioned(
            right: 16,
            bottom: 24,
            child: _MyLocationButton(
              loading: _locating,
              onTap: _goToMyLocation,
            ),
          ),
        ],
      ),
    );
  }
}

/// 앱 디자인에 맞춘 시설물 검색창.
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
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '시설·장소 검색...',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 앱 디자인에 맞춘 내 위치 버튼.
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
                      valueColor:
                          AlwaysStoppedAnimation(AppColors.primaryDark),
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
