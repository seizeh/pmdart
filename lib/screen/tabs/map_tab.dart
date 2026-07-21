import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../../theme/app_palette.dart';
import '../../motion/motion.dart';
import '../../services/facility_repository.dart';
import '../../services/community_repository.dart';
import '../../services/location_service.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/facility_sheet.dart';
import '../../widgets/map_bottom_sheet.dart';
import '../../widgets/region_posts_sheet.dart';

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
  // 마커는 지도 이미지 위 비트맵이라 모드 무관 — 정적 브라운 유지.
  return const Color(0xFF5A4E3A);
}

// 카테고리 칩 통일 색(선택 배경).
const _catAccent = Color(0xFFAC9466);
// 마커 아이콘 단색 — 라이트: 기존 진브라운, 다크: 검색 핀 테두리와 같은 골드.
// 지도와의 대비는 색 대신 부드러운 그림자로 확보한다.
const _markerIconLight = Color(0xFF5A4E38);
const _markerIconDark = _catAccent;
const _markerShadow = Color(0x73000000);
// 지도 위 마커 캡션/틴트 — 지도 모드(라이트 타일/나이트 타일) 기준 색.
const _markerCaptionLight = Color(0xFF5A4E3A);
const _markerCaptionDark = Color(0xFFE8E2D5);
const _markerHaloLight = Colors.white;
const _markerHaloDark = Color(0xFF1E1E1E);

IconData _iconForCat(String code) => switch (code) {
  'animal_hospital' => Icons.local_hospital_outlined,
  'grooming' => Icons.content_cut,
  'pet_hotel' => Icons.hotel_outlined,
  'pet_sales' => Icons.storefront_outlined,
  'pet_cafe' => Icons.local_cafe_outlined,
  'posts' => Icons.article_outlined,
  _ => Icons.place_outlined,
};

// 지도 마커 전용: 속이 채워진(filled) 변형으로 가독성↑. 단, 가위·침대는 채운 변형이
// 없거나 어색해 예외로 라인 아이콘 유지.
IconData _markerIconForCat(String code) => switch (code) {
  'animal_hospital' => Icons.local_hospital,
  'grooming' => Icons.content_cut, // 예외(라인 유지)
  'pet_hotel' => Icons.hotel, // 예외(라인 유지)
  'pet_sales' => Icons.storefront,
  'pet_cafe' => Icons.local_cafe,
  'posts' => Icons.article,
  _ => Icons.place,
};

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

class _MapTabState extends State<MapTab> with AutomaticKeepAliveClientMixin {
  // pmdb 0023: 맵은 앱에 1개만 두고 살려둔다. 스왑(상세 표시)으로 잠시 빌드가 빠져도
  // 탭 상태(_detailFacility/_lastCamera 등)는 keep-alive 로 유지.
  @override
  bool get wantKeepAlive => true;

  NaverMapController? _controller;
  final _searchController = TextEditingController();
  bool _locating = false;
  bool _loadingFac = false;

  // 시설/게시글 시트는 지도를 트리에서 빼지 않고(= 재생성 없음) 라이브 지도 위에
  // 그대로 올린다. 과거의 "PlatformView 위 모달 합성 충돌" 가설은 실제로는 본문의
  // 무한너비 버그였고(#28), 그건 MapBottomSheet 의 Align>SizedBox 가 잡아준다.
  // (스냅샷으로 얼리는 우회는 불필요 — 지도가 살아있어 닫을 때 재로딩이 없다.)
  Widget? _sheetChild;
  double _sheetHeight = 0.6;
  // 첫 진입 시 카메라 기준(시트는 지도를 유지하므로 평소엔 재생성 안 됨).
  NCameraPosition? _lastCamera;

  // 선택된 카테고리(기본 전체). 마커 id → Facility(탭 시 바텀시트용).
  // 카테고리는 단일 선택(한 번에 하나만 표시) — 사업 카테고리가 겹치기 때문.
  final Set<String> _selected = {'animal_hospital'};
  final Map<String, Facility> _byMarkerId = {};
  final Map<String, NOverlayImage?> _catIcons = {}; // 카테고리별 마커 아이콘 캐시
  // 인증 업체 마커(대표 사진) 캐시 — 시설 id + 사진 URL 키(사진 교체 시 재렌더).
  final Map<String, NOverlayImage?> _bizIcons = {};
  final Map<String, PostCluster> _clusterByMarkerId = {}; // 게시글 클러스터 마커
  bool _dongSynced = false; // 세션당 1회 행정동 centroid 보충
  NLatLng? _loadedCenter; // 마지막 조회 중심(디바운스 기준)

  Facility? _searchResult; // 검색으로 선택된 시설(강조 마커, 재조회에도 유지)
  final _searchFocus = FocusNode(); // 검색창 포커스 — 탭 시 카테고리 초기화
  String? _suggestCat; // 검색 목록 카테고리 필터(null=전체)
  NOverlayImage? _searchIcon; // 검색 강조 마커 아이콘(IMG_3 핀, 캐시)
  List<Facility> _suggestions = const []; // 자동완성 후보
  Timer? _suggestDebounce;

  // 네이버 지도 커스텀 스타일(지도 스타일 에디터에서 발급한 ID). 라이트/다크
  // 각각 색상·심볼 제외까지 포함한 완전한 스타일.
  static const _lightStyleId = '430d08d6-8afd-4661-9ffe-bcbf5c4351f4';
  static const _darkStyleId = '02402e67-1834-487e-a46b-064c89b7d26b';
  static const _defaultZoom = 14.0;
  static const _seoul = NLatLng(37.5666, 126.9784);
  static const _initialPosition = NCameraPosition(
    target: _seoul,
    zoom: _defaultZoom,
  );

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocus);
  }

  // 테마(라이트↔다크) 전환 감지 — 지도는 나이트 모드로 자동 전환되지만,
  // 이미 그려진 마커 캡션 색은 남아 있으므로 다시 그린다.
  Brightness? _lastBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    if (_lastBrightness != null && _lastBrightness != b) {
      _catIcons.clear(); // 마커 아이콘 색이 모드별로 달라 다시 렌더
      _bizIcons.clear(); // 인증 마커도 링·배지 색이 모드별
      final center = _loadedCenter;
      if (center != null) _loadFacilities(center);
    }
    _lastBrightness = b;
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchFocus.removeListener(_onSearchFocus);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 검색 모드 — 검색창에 포커스가 있거나 자동완성 목록이 떠 있는 동안.
  /// 이때 카테고리 칩은 지도 레이어가 아니라 **검색 목록 필터**로 동작한다.
  bool get _searchMode => _searchFocus.hasFocus || _suggestions.isNotEmpty;

  /// 검색창 탭(포커스 진입) → 카테고리 선택 초기화 + 마커 정리(검색 모드 진입).
  void _onSearchFocus() {
    if (!_searchFocus.hasFocus) {
      // 포커스 해제 자체로는 아무것도 하지 않는다(목록/필터는 유지).
      if (mounted) setState(() {});
      return;
    }
    if (_selected.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _selected.clear();
      _suggestCat = null;
    });
    final center = _loadedCenter;
    if (center != null) _loadFacilities(center);
  }

  /// 반경 5km 시설 조회 → 마커 갱신.
  Future<void> _loadFacilities(NLatLng center) async {
    final c = _controller;
    if (c == null) return;
    // 마커 캡션 색 — 지도 모드에 맞춰(await 전에 캡처).
    final dark = context.isDark;
    final capColor = dark ? _markerCaptionDark : _markerCaptionLight;
    final capHalo = dark ? _markerHaloDark : _markerHaloLight;
    setState(() => _loadingFac = true);
    try {
      // 공공데이터(DB) 카테고리만 — 'pet_cafe'(실시간)·'posts'(게시글)는 제외.
      final dbCats = _selected
          .where((cat) => cat != 'pet_cafe' && cat != _postsLayer.$1)
          .toList();
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
      // 첫 진입 시 행정동 중심좌표를 1회 보충(지오코딩) 후 클러스터 조회.
      List<PostCluster> clusters = const [];
      if (_selected.contains('posts')) {
        if (!_dongSynced) {
          _dongSynced = true;
          await CommunityRepository.instance.syncDongCentroids();
        }
        clusters = await _loadClusters(c);
      }

      await c.clearOverlays(type: NOverlayType.marker);
      _byMarkerId.clear();
      _clusterByMarkerId.clear();
      final markers = <NAddableOverlay>{};
      // 인증 마커끼리 충돌하면 먼저 인증한 업체가 살아남게 — 승인 시각
      // 오름차순 순위(이른 승인 = 높은 zIndex). 시각 미상은 최하위.
      final verifiedRank = <String, int>{};
      final vs =
          rows
              .where((f) => f.ownerUserId != null && !isLowTrustHidden(f))
              .toList()
            ..sort((a, b) {
              final at = a.ownerVerifiedAt, bt = b.ownerVerifiedAt;
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return at.compareTo(bt);
            });
      for (final (i, f) in vs.indexed) {
        verifiedRank[f.id] = i;
      }
      for (final f in rows) {
        // 분양 신뢰도가 너무 낮으면(점수 ≤ -2) 비분양 추정이 강해 지도에서 제외.
        // -1 은 남기되 캡션에 ⚠ 로 경고만 한다.
        if (isLowTrustHidden(f)) continue;
        final sales = evaluatePetSales(f);
        final id = 'fac_${f.id}';
        // 인증 업체(연결 업주 존재)는 강조 마커 — 둥근 정사각형 대표 사진
        // (없으면 같은 실루엣의 글리프 폴백) + 체크 배지.
        final verified = f.ownerUserId != null;
        final icon = verified
            ? await _verifiedIcon(f)
            : await _iconFor(f.category);
        final warn = sales?.level == PetSalesTrust.caution;
        final m = NMarker(id: id, position: NLatLng(f.lat, f.lng), icon: icon)
          ..setIsHideCollidedMarkers(true)
          // 겹치는 네이버 기본 POI 심볼(아파트 상호명 등)은 숨겨 앱 카테고리 마커를 우선.
          ..setHideCollidedSymbols(true)
          ..setCaption(
            NOverlayCaption(
              text: warn ? '⚠ ${_wrapCaption(f.name)}' : _wrapCaption(f.name),
              textSize: 11,
              color: capColor,
              haloColor: capHalo,
            ),
          )
          ..setIsHideCollidedCaptions(true)
          ..setOnTapListener((_) => _showFacilitySheet(f));
        // 마커가 겹치면 인증 업체가 항상 살아남게 — 기본(200000)보다 위,
        // 검색 강조 마커(1000000)보다는 아래. 인증끼리는 먼저 인증한 쪽 우선.
        if (verified) {
          m.setGlobalZIndex(200199 - (verifiedRank[f.id] ?? 99).clamp(0, 99));
        }
        if (icon != null) {
          m.setAnchor(const NPoint(0.5, 0.5)); // 원형 아이콘 → 중앙 앵커
        } else {
          m.setIconTintColor(_catAccent); // 아이콘 로드 실패 시 폴백(통일색)
        }
        _byMarkerId[id] = f;
        markers.add(m);
      }
      for (final cl in clusters) {
        final id = 'cluster_${cl.regionCode}';
        // 동 중심에 게시글 수 배지(탭 시 그 동 게시글 목록). 없으면 캡션 폴백.
        final badge = await _clusterBadge(cl.count);
        final m =
            NMarker(id: id, position: NLatLng(cl.lat, cl.lng), icon: badge)
              ..setAnchor(const NPoint(0.5, 0.5))
              ..setOnTapListener((_) => _showRegionPosts(cl));
        if (badge == null) {
          m.setCaption(
            NOverlayCaption(
              text: '게시글 ${cl.count}',
              color: _postsLayer.$3,
              haloColor: Colors.white,
            ),
          );
        }
        _clusterByMarkerId[id] = cl;
        markers.add(m);
      }
      // 검색으로 선택된 시설 강조 마커(카테고리/반경과 무관하게 항상 표시).
      final sr = _searchResult;
      if (sr != null) markers.add(await _buildSearchMarker(sr));
      if (markers.isNotEmpty) await c.addOverlayAll(markers);
      _loadedCenter = center;
    } catch (_) {
      // 오류가 나도 이전 마커는 제거(선택 해제한 카테고리 마커가 남지 않도록).
      try {
        await c.clearOverlays(type: NOverlayType.marker);
      } catch (_) {
        /* 무시 */
      }
      _byMarkerId.clear();
      _clusterByMarkerId.clear();
      if (mounted) {
        final msg = _selected.contains(_postsLayer.$1) && _selected.length == 1
            ? '게시글을 불러오지 못했어요'
            : '주변 시설을 불러오지 못했어요';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
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

  /// 동 중심에 표시할 게시글 수 배지(위젯 → 오버레이 이미지). 실패 시 null.
  Future<NOverlayImage?> _clusterBadge(int count) async {
    try {
      return await NOverlayImage.fromWidget(
        context: context,
        widget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _postsLayer.$3,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              const Text(
                '게시글',
                style: TextStyle(color: Colors.white, fontSize: 9, height: 1.3),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// 클러스터 탭 → 그 행정동 게시글 목록(지도 위 바텀시트).
  void _showRegionPosts(PostCluster cl) {
    showSheetOverMap(RegionPostsContent(cluster: cl), heightFactor: 0.7);
  }

  /// 지도 준비 → 현재 위치로 이동 + 시설 조회. 위치 실패 시 서울 기준.
  Future<void> _initLoad() async {
    final c = _controller;
    if (c == null) return;
    // 스왑 복귀로 지도가 재생성된 경우: 현재위치 점프 없이 직전 화면/마커만 복원.
    if (_lastCamera != null) {
      await _loadFacilities(_lastCamera!.target);
      return;
    }
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
            duration: const Duration(milliseconds: 350),
          ),
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
    // 주의: 여기서 unfocus 하면 검색창 탭 → 키보드가 뜰 때의 지도 리레이아웃이
    // onCameraIdle 을 유발해 키보드가 바로 닫힌다. 키보드 해제는 onMapTapped/배리어가 담당.
    final c = _controller;
    if (c == null || _loadedCenter == null || _loadingFac) return;
    final cam = await c.getCameraPosition();
    _lastCamera = cam; // 스왑 후 복원용
    final moved = Geolocator.distanceBetween(
      _loadedCenter!.latitude,
      _loadedCenter!.longitude,
      cam.target.latitude,
      cam.target.longitude,
    );
    if (moved > 1000) await _loadFacilities(cam.target);
  }

  // 카테고리 단일 선택(게시글 포함 한 번에 하나만). 같은 칩을 다시 누르면 해제.
  // 검색 모드에서는 지도 레이어가 아니라 검색 목록 필터로 동작한다.
  void _toggleCategory(String code) {
    if (_searchMode) {
      // 게시글은 시설 검색 대상이 아니라 필터로 선택 불가(추후 기능 확장 시 지원).
      if (code == _postsLayer.$1) return;
      setState(() {
        _suggestCat = (_suggestCat == code) ? null : code;
        // 칩 하이라이트도 필터와 동기화.
        _selected.clear();
        if (_suggestCat != null) _selected.add(_suggestCat!);
      });
      return;
    }
    setState(() {
      if (_selected.contains(code)) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..add(code);
      }
    });
    final center = _loadedCenter;
    if (center == null) return;
    if (code == _postsLayer.$1 && _selected.contains(code)) {
      _loadPostsAndNotify(center);
    } else {
      _loadFacilities(center);
    }
  }

  /// 카테고리 마커 아이콘(캐시). PNG 를 흰 원형 핀에 합성해 일관/또렷하게.
  Future<NOverlayImage?> _iconFor(
    String category, {
    bool verified = false,
  }) async {
    final key = verified ? '$category|v' : category; // 인증 변형은 별도 캐시
    if (_catIcons.containsKey(key)) return _catIcons[key];
    // 모드별 아이콘 색 — await 전에 캡처(빌드 컨텍스트 안전).
    final color = context.isDark ? _markerIconDark : _markerIconLight;
    final dark = context.isDark;
    NOverlayImage? out;
    try {
      out = await _renderMarkerIcon(
        category,
        color,
        verified: verified,
        dark: dark,
      );
    } catch (_) {
      out = null;
    }
    _catIcons[key] = out;
    return out;
  }

  /// 이미지의 불투명 픽셀 경계상자(투명 여백 제외). 불투명 픽셀이 없으면 전체.
  Future<Rect> _opaqueBounds(ui.Image img) async {
    final w = img.width, h = img.height;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final px = data.buffer.asUint8List();
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (px[(y * w + x) * 4 + 3] > 16) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < minX) return Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  // 인증 마커 공통 도형 상수 — 캔버스 104px, 둥근 정사각형 84×84 r22.
  static const _bizTarget = 104.0;
  static const _bizBox = 84.0;
  static const _bizRadius = 22.0;

  /// 인증 마커의 둥근 정사각형 프레임(그림자 + 채움/클립 + 모드별 분리 링).
  /// [fillColor] 를 주면 채우고(글리프 폴백), 없으면 클립만 남긴다(사진 마커 —
  /// 호출자가 클립 안에 사진을 그린 뒤 [_drawBizFrameRing] 으로 링을 얹는다).
  RRect _bizFrameRRect() => RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: const Offset(_bizTarget / 2, _bizTarget / 2),
      width: _bizBox,
      height: _bizBox,
    ),
    const Radius.circular(_bizRadius),
  );

  void _drawBizFrame(Canvas canvas, bool dark, {Color? fillColor}) {
    final rrect = _bizFrameRRect();
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = _markerShadow
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
    if (fillColor != null) canvas.drawRRect(rrect, Paint()..color = fillColor);
    _drawBizFrameRing(canvas, dark);
  }

  void _drawBizFrameRing(Canvas canvas, bool dark) {
    canvas.drawRRect(
      _bizFrameRRect(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = dark ? _markerHaloDark : _markerHaloLight,
    );
  }

  /// 인증 배지 — 우상단 골드(액센트) 원 + 흰 체크. 프레임과 링으로 분리.
  void _drawVerifiedBadge(Canvas canvas, bool dark) {
    const bc = Offset(_bizTarget - 20, 20);
    const br = 15.0;
    canvas.drawCircle(
      bc + const Offset(0, 1.5),
      br,
      Paint()
        ..color = _markerShadow
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    canvas.drawCircle(bc, br, Paint()..color = _catAccent);
    canvas.drawCircle(
      bc,
      br,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = dark ? _markerHaloDark : _markerHaloLight,
    );
    final check = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.check_rounded.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: Icons.check_rounded.fontFamily,
          color: Colors.white,
        ),
      )
      ..layout();
    check.paint(canvas, bc - Offset(check.width / 2, check.height / 2));
  }

  /// 인증 업체 마커 — 둥근 정사각형 안에 대표 사진(업체 프로필 얼굴).
  /// 사진이 없거나 로드 실패면 같은 실루엣의 글리프 폴백(_renderMarkerIcon).
  /// 캐시 키는 사진 URL+초점 기준 — 다중 카테고리(같은 업체의 형제 행)가
  /// 같은 사진을 행마다 다시 받아 렌더하지 않게. 사진 없으면 카테고리 기준.
  Future<NOverlayImage?> _verifiedIcon(Facility f) async {
    final key = f.ownerPhotoUrl != null
        ? 'p|${f.ownerPhotoUrl}|${f.ownerPhotoAlignY}'
        : 'g|${f.category}';
    if (_bizIcons.containsKey(key)) return _bizIcons[key];
    final dark = context.isDark; // await 전에 캡처
    NOverlayImage? out;
    try {
      ui.Image? photo;
      final url = f.ownerPhotoUrl;
      if (url != null) {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          // 마커 크기로만 쓰므로 소형 디코딩(원본 비율 유지).
          final codec = await ui.instantiateImageCodec(
            res.bodyBytes,
            targetWidth: 240,
          );
          photo = (await codec.getNextFrame()).image;
        }
      }
      if (photo != null) {
        out = await _renderBizPhotoIcon(photo, f.ownerPhotoAlignY, dark);
        photo.dispose();
      } else {
        out = await _iconFor(f.category, verified: true);
      }
    } catch (_) {
      out = null;
    }
    _bizIcons[key] = out;
    return out;
  }

  /// 둥근 정사각형 사진 마커 렌더 — cover 크롭 + 업주 세로 초점(alignY,
  /// 상세 히어로와 동일 문법) + 분리 링 + 체크 배지.
  Future<NOverlayImage?> _renderBizPhotoIcon(
    ui.Image photo,
    double alignY,
    bool dark,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rrect = _bizFrameRRect();
    final dst = rrect.outerRect;
    _drawBizFrame(canvas, dark); // 그림자 + 링(사진은 클립 안에)
    canvas.save();
    canvas.clipRRect(rrect);
    final scale = math.max(dst.width / photo.width, dst.height / photo.height);
    final srcW = dst.width / scale, srcH = dst.height / scale;
    final srcX = (photo.width - srcW) / 2;
    final srcY = (photo.height - srcH) * (alignY.clamp(-1.0, 1.0) + 1) / 2;
    canvas.drawImageRect(
      photo,
      Rect.fromLTWH(srcX, srcY, srcW, srcH),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    _drawBizFrameRing(canvas, dark); // 링은 사진 위에 다시(경계 또렷하게)
    _drawVerifiedBadge(canvas, dark);
    final image = await recorder.endRecording().toImage(
      _bizTarget.toInt(),
      _bizTarget.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    return NOverlayImage.fromByteArray(bytes.buffer.asUint8List());
  }

  /// 마커 아이콘: 분양은 IMG_4.png, 나머지는 채운 Material 아이콘을 #5a4e38 로 렌더.
  /// 흰 배경 없음. 가독성용 흰 외곽선은 블러 없이 오프셋으로 그려 Impeller 안전.
  ///
  /// [verified] (사진 없는 인증 업체 폴백)는 실루엣 자체가 다르게 — 브랜드
  /// 컬러로 채운 둥근 정사각형 위에 반전색 글리프, 우상단에 체크 배지.
  Future<NOverlayImage?> _renderMarkerIcon(
    String category,
    Color iconColor, {
    bool verified = false,
    bool dark = false,
  }) async {
    final iconSize = verified ? 50.0 : 88.0; // 디스크 안에 들어가는 글리프는 축소
    const target = 104.0; // 88 + pad 8*2 — 앵커 계산이 같도록 캔버스 크기 고정
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 인증 업체(사진 없음 폴백): 브랜드 컬러로 채운 둥근 정사각형 —
    // 사진 마커(_renderBizPhotoIcon)와 같은 실루엣. 글리프는 반전색.
    final contentColor = verified
        ? (dark ? const Color(0xFF241F16) : Colors.white)
        : iconColor;
    if (verified) {
      final fill = dark ? const Color(0xFFD8C7A9) : const Color(0xFF5A4E3A);
      _drawBizFrame(canvas, dark, fillColor: fill);
    }

    if (category == 'pet_sales') {
      // 분양: IMG_4.png(브라운 발바닥)를 투명 여백 잘라 중앙 배치 —
      // 다른 마커와 같은 흰색으로 틴트하고, 그림자로 지도와 대비.
      final data = await rootBundle.load('assets/images/IMG_4.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final src = await _opaqueBounds(img);
      final s = iconSize / (src.width > src.height ? src.width : src.height);
      final dw = src.width * s, dh = src.height * s;
      final dx = (target - dw) / 2, dy = (target - dh) / 2;
      final dst = Rect.fromLTWH(dx, dy, dw, dh);
      // 디스크가 그림자를 담당 — 글리프 그림자는 비인증만.
      if (!verified) {
        canvas.drawImageRect(
          img,
          src,
          dst.shift(const Offset(0, 2)),
          Paint()
            ..filterQuality = FilterQuality.high
            ..colorFilter = const ui.ColorFilter.mode(
              _markerShadow,
              ui.BlendMode.srcIn,
            )
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
        );
      }
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.high
          ..colorFilter = ui.ColorFilter.mode(contentColor, ui.BlendMode.srcIn),
      );
      img.dispose();
    } else {
      final iconData = _markerIconForCat(category);
      final ch = String.fromCharCode(iconData.codePoint);
      TextPainter glyph(Color color) {
        return TextPainter(textDirection: TextDirection.ltr)
          ..text = TextSpan(
            text: ch,
            style: TextStyle(
              fontSize: iconSize,
              fontFamily: iconData.fontFamily,
              package: iconData.fontPackage,
              color: color,
            ),
          )
          ..layout();
      }

      final base = glyph(contentColor);
      final origin = Offset(
        (target - base.width) / 2,
        (target - base.height) / 2,
      );
      // 아이콘 전체를 외곽선 색(흰색) 단색으로 — 부드러운 그림자만으로
      // 라이트/나이트 지도 어느 쪽에서도 대비를 확보한다.
      // (인증 마커는 디스크가 그림자·대비를 담당하므로 글리프 그림자 생략.)
      if (!verified) {
        final shadow = glyph(_markerShadow);
        canvas.saveLayer(
          null,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        );
        shadow.paint(canvas, origin + const Offset(0, 2));
        canvas.restore();
      }
      base.paint(canvas, origin);
    }

    if (verified) _drawVerifiedBadge(canvas, dark);

    final image = await recorder.endRecording().toImage(
      target.toInt(),
      target.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    return NOverlayImage.fromByteArray(bytes.buffer.asUint8List());
  }

  /// 검색 강조 마커 아이콘(IMG_3 핀). 투명 여백을 잘라 적당한 크기로 렌더(캐시).
  Future<NOverlayImage?> _loadSearchIcon() async {
    if (_searchIcon != null) return _searchIcon;
    try {
      const targetH = 120.0; // 핀 높이(px) — 너무 크지도 작지도 않은 크기.
      final data = await rootBundle.load('assets/images/IMG_3.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final src = await _opaqueBounds(img); // 투명 여백 제거(원본 여백이 큼)
      final scale = targetH / src.height;
      final w = (src.width * scale).round();
      final h = targetH.round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      img.dispose();
      final image = await recorder.endRecording().toImage(w, h);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes != null) {
        _searchIcon = await NOverlayImage.fromByteArray(
          bytes.buffer.asUint8List(),
        );
      }
    } catch (_) {
      _searchIcon = null;
    }
    return _searchIcon;
  }

  /// 검색 강조 마커 1건(id 'search'). 카테고리/반경과 무관하게 항상 최상단.
  /// 핀(IMG_3)은 끝이 아래를 향하므로 앵커는 하단 중앙. 로드 실패 시 기본 핀 폴백.
  Future<NMarker> _buildSearchMarker(Facility sr) async {
    final dark = context.isDark; // await 전에 캡처
    final icon = await _loadSearchIcon();
    final m =
        NMarker(id: 'search', position: NLatLng(sr.lat, sr.lng), icon: icon)
          ..setGlobalZIndex(1000000)
          ..setHideCollidedSymbols(true) // 겹치는 네이티브 심볼 숨김(강조 마커 우선)
          ..setCaption(
            NOverlayCaption(
              text: _wrapCaption(sr.name),
              textSize: 13,
              color: dark ? _markerCaptionDark : _markerCaptionLight,
              haloColor: dark ? _markerHaloDark : _markerHaloLight,
            ),
          )
          ..setOnTapListener((_) => _showFacilitySheet(sr));
    if (icon != null) {
      m.setAnchor(const NPoint(0.5, 1.0)); // 핀 끝(아래)이 좌표를 가리키게
    } else {
      m.setIconTintColor(dark ? _markerCaptionDark : _markerCaptionLight);
    }
    return m;
  }

  /// 게시글 레이어를 켤 때, 현재 화면에 조회된 게시글이 없으면 안내.
  Future<void> _loadPostsAndNotify(NLatLng center) async {
    await _loadFacilities(center);
    if (mounted &&
        _selected.contains(_postsLayer.$1) &&
        _clusterByMarkerId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 지역에 조회된 게시글이 없어요')));
    }
  }

  /// 시설 상세(정보 + 후기/사진 + 후기 작성 + 네이버 지도 링크) — 지도 위 바텀시트.
  void _showFacilitySheet(Facility f) {
    showSheetOverMap(
      FacilityDetailContent(
        facility: f,
        color: _colorFor(f.category),
        label: kFacilityLabels[f.category] ?? f.category,
      ),
    );
  }

  /// 라이브 지도 위에 [MapBottomSheet] 로 [content] 를 올린다(재사용).
  /// 지도는 트리에 그대로 유지되므로 닫아도 재생성/재로딩이 없다(#28→#29 후속).
  /// 시트가 폭을 Align>SizedBox 로 고정하므로 [content] 는 일반 위젯(Expanded/Spacer/
  /// 머티리얼)도 안전. [heightFactor] 로 시트 높이 조절.
  void showSheetOverMap(Widget content, {double heightFactor = 0.6}) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _sheetChild = content;
      _sheetHeight = heightFactor;
    });
  }

  void _closeSheetOverMap() {
    setState(() => _sheetChild = null);
    // 지도는 그대로 살아있어 즉시 다시 보인다(재로딩 없음).
  }

  /// 시설명 검색 → 가장 가까운 결과로 카메라 이동 + 상세 시트.
  Future<void> _onSearchSubmitted(String query) async {
    final q = query.trim();
    final c = _controller;
    if (q.isEmpty || c == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final center = _loadedCenter;
    final results = <Facility>[];
    try {
      // DB 시설(이름) + 애견카페(실시간 이름검색) 동시 조회 후 거리순 병합.
      final lists = await Future.wait([
        FacilityRepository.instance.searchByName(
          q,
          lat: center?.latitude,
          lng: center?.longitude,
        ),
        if (center != null)
          FacilityRepository.instance.searchPetCafes(
            lat: center.latitude,
            lng: center.longitude,
            query: q,
            radiusM: double.infinity, // 이름 검색은 거리 무관
          )
        else
          Future.value(<Facility>[]),
      ]);
      results
        ..addAll(lists[0])
        ..addAll(lists[1])
        ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    } catch (_) {
      /* 빈 결과 처리 */
    }
    if (!mounted) return;
    if (results.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$q" 검색 결과가 없어요')));
      return;
    }
    if (mounted) await _goToFacility(results.first);
  }

  /// 입력 변화 → 디바운스 후 자동완성 후보(시설명, DB) 조회.
  void _onSuggestChanged(String v) {
    _suggestDebounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () async {
      final center = _loadedCenter;
      final merged = <Facility>[];
      try {
        // DB 시설(이름) + 애견카페(실시간 이름검색) 병합 → 거리순.
        final lists = await Future.wait([
          FacilityRepository.instance.searchByName(
            q,
            lat: center?.latitude,
            lng: center?.longitude,
          ),
          if (center != null)
            FacilityRepository.instance.searchPetCafes(
              lat: center.latitude,
              lng: center.longitude,
              query: q,
              radiusM: double.infinity,
            )
          else
            Future.value(<Facility>[]),
        ]);
        merged
          ..addAll(lists[0])
          ..addAll(lists[1])
          ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
      } catch (_) {
        /* 빈 결과 */
      }
      if (!mounted || _searchController.text.trim() != q) return;
      // 카테고리 필터를 걸어도 후보가 남도록 넉넉히 유지(목록은 스크롤).
      setState(() => _suggestions = merged.take(20).toList());
    });
  }

  /// 지도 빈 공간 탭 → 검색 강조 마커(표시목) 즉시 제거. 검색창 텍스트는 유지.
  Future<void> _clearSearchHighlight() async {
    if (_searchResult == null) return;
    setState(() => _searchResult = null);
    final c = _controller;
    if (c == null) return;
    try {
      await c.deleteOverlay(
        const NOverlayInfo(type: NOverlayType.marker, id: 'search'),
      );
    } catch (_) {
      /* 이미 없으면 무시 */
    }
  }

  void _clearSearch() {
    _suggestDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _suggestions = const [];
      _suggestCat = null;
      _searchResult = null;
    });
    final center = _loadedCenter;
    if (center != null) _loadFacilities(center); // 강조 마커 제거 반영
  }

  /// 검색 결과/후보 선택 → 카메라 이동 + 강조 마커 + 상세 시트.
  Future<void> _goToFacility(Facility f) async {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _searchResult = f;
      _suggestions = const [];
      _suggestCat = null;
      _selected.clear(); // 검색 확정 → 강조 마커만 남긴다(칩은 필터 역할 종료)
    });
    _searchController.text = f.name;
    FocusManager.instance.primaryFocus?.unfocus();
    // 강조 마커를 즉시 올린다. onCameraIdle 재조회는 중심이 1km 이상 움직여야만
    // 일어나서, 가까운 곳을 탭하면 마커가 안 뜨던 문제를 직접 추가로 해결.
    try {
      await c.deleteOverlay(
        const NOverlayInfo(type: NOverlayType.marker, id: 'search'),
      );
    } catch (_) {
      /* 직전 강조 마커 없음 */
    }
    try {
      await c.addOverlay(await _buildSearchMarker(f));
    } catch (_) {
      /* 마커 추가 실패는 무시 */
    }
    await c.updateCamera(
      NCameraUpdate.scrollAndZoomTo(target: NLatLng(f.lat, f.lng), zoom: 16)
        ..setAnimation(
          animation: NCameraAnimation.easing,
          duration: const Duration(milliseconds: 400),
        ),
    );
    // 상세 시트 즉시 표시(마커는 위에서 이미 추가됨).
    if (mounted) _showFacilitySheet(f);
  }

  /// 자동완성 후보 드롭다운 — 카테고리 칩(_suggestCat)으로 필터링된다.
  Widget _buildSuggestions() {
    final shown = _suggestCat == null
        ? _suggestions
        // 겸업 업체(형제 통합)는 여러 카테고리를 가지므로 '포함'으로 판별 —
        // 미용+분양 업체가 미용·분양 어느 칩에서도 보이게(검색 dedupe 후).
        : _suggestions
              .where((f) => f.categories.contains(_suggestCat))
              .toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: shown.isEmpty
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '해당 카테고리의 검색 결과가 없어요',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: shown.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.colors.border),
              itemBuilder: (_, i) {
                final f = shown[i];
                final dist = f.distanceM <= 0
                    ? ''
                    : (f.distanceM < 1000
                          ? '${f.distanceM.round()}m'
                          : '${(f.distanceM / 1000).toStringAsFixed(1)}km');
                return InkWell(
                  onTap: () => _goToFacility(f),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                              if (f.address != null && f.address!.isNotEmpty)
                                Text(
                                  f.address!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.colors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (dist.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              dist,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAlive 필수 호출

    // 지도는 시트가 열려도 트리에 그대로 유지한다(dispose/재생성 안 함 → 닫을 때
    // 타일·마커 재로딩 없이 즉시 복귀). 시트가 열리면 라이브 지도 위에 바로
    // MapBottomSheet 를 올린다(스크림이 지도를 어둡게, 본문 폭은 시트의 Align>SizedBox
    // 가 고정 → #28 무한너비 해결). 안드로이드 뒤로가기는 시트가 열려 있으면 닫기.
    final sheetOpen = _sheetChild != null;
    return PopScope(
      canPop: !sheetOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && sheetOpen) _closeSheetOverMap();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: Stack(
          children: [
            ClipRect(
              child: NaverMap(
                options: NaverMapViewOptions(
                  initialCameraPosition: _lastCamera ?? _initialPosition,
                  // 다크: 내비 지도 + 야간 모드(nightModeEnable 은 navi 에서만
                  // 공식 지원). 이 조합이어야 SDK 가 isDark 로 판단해 네이버
                  // 로고를 다크용으로 자동 교체한다. 색상·심볼은 라이트/다크
                  // 각각의 커스텀 스타일이 담당(둘 다 정보 최소화 동일 밀도).
                  mapType: context.isDark ? NMapType.navi : NMapType.basic,
                  customStyleId: context.isDark ? _darkStyleId : _lightStyleId,
                  nightModeEnable: context.isDark,
                  locationButtonEnable: false,
                  consumeSymbolTapEvents: false,
                  // 네이버 로고를 하단 메뉴바 바로 위로 올린다(내 위치 버튼과 같은 높이).
                  logoMargin: EdgeInsets.only(
                    left: 12,
                    bottom: 20 + MediaQuery.of(context).padding.bottom,
                  ),
                ),
                onMapReady: (controller) {
                  _controller = controller;
                  _initLoad();
                },
                onCameraIdle: _onCameraIdle,
                // 지도는 네이티브 뷰라 루트 GestureDetector 가 탭을 못 받는다.
                // 지도 빈 공간 탭 → 키보드 닫기 + 검색 강조 마커(표시목) 제거.
                // (마커 아이콘 탭은 onMapTapped 가 아니라 마커 onTap → 상세 시트.)
                onMapTapped: (_, _) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _clearSearchHighlight();
                },
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

            // 시트 오버레이: 라이브 지도 위에 바로(스크림이 지도를 어둡게 처리).
            if (sheetOpen)
              Positioned.fill(
                child: MapBottomSheet(
                  onClose: _closeSheetOverMap,
                  heightFactor: _sheetHeight,
                  child: _sheetChild!,
                ),
              ),

            // 지도 UI(검색/칩/로딩/내위치) — 시트가 열리면 숨김.
            if (!sheetOpen) ...[
              // 상단: 검색창 + 카테고리 필터칩
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Column(
                          children: [
                            _SearchField(
                              controller: _searchController,
                              focusNode: _searchFocus,
                              onSubmitted: _onSearchSubmitted,
                              onChanged: _onSuggestChanged,
                              onClear: _clearSearch,
                            ),
                            if (_suggestions.isNotEmpty) _buildSuggestions(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          // 좌우 여백은 뷰포트 안쪽 패딩으로 — 칩이 화면
                          // 가장자리까지 스크롤돼 나간다(커뮤니티 칩과 동일).
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final (i, c) in _facilityCats.indexed)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Entrance(
                                  index: i,
                                  offsetY: 6,
                                  child: _CatChip(
                                    label: c.$2,
                                    icon: _iconForCat(c.$1),
                                    selected: _selected.contains(c.$1),
                                    onTap: () => _toggleCategory(c.$1),
                                  ),
                                ),
                              ),
                            // 게시글 클러스터 레이어(시설과 별개).
                            // 검색 모드에선 필터 대상이 아니라 흐리게(선택 불가).
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Entrance(
                                index: _facilityCats.length,
                                offsetY: 6,
                                child: Opacity(
                                  opacity: _searchMode ? 0.35 : 1.0,
                                  child: _CatChip(
                                    label: _postsLayer.$2,
                                    icon: _iconForCat(_postsLayer.$1),
                                    selected: _selected.contains(
                                      _postsLayer.$1,
                                    ),
                                    onTap: () =>
                                        _toggleCategory(_postsLayer.$1),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_loadingFac)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(top: 120),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    ),
                  ),
                ),

              Positioned(
                right: 16,
                // 하단 바(약 62)+안전영역 바로 위에 붙도록(가려지지 않는 선에서 최대한 내림).
                bottom: 58 + MediaQuery.of(context).padding.bottom,
                child: _MyLocationButton(
                  loading: _locating,
                  onTap: _goToMyLocation,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 카테고리 필터 칩.
class _CatChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CatChip> createState() => _CatChipState();
}

class _CatChipState extends State<_CatChip>
    with SingleTickerProviderStateMixin {
  // 선택 상태 0↔1 을 스프링으로 전환 — 색/스케일이 물리적으로 이어진다(오버슈트 팝).
  late final AnimationController _sel = AnimationController.unbounded(
    vsync: this,
    value: widget.selected ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _CatChip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _sel.springTo(
        widget.selected ? 1 : 0,
        spring: widget.selected ? MotionSprings.bounce : MotionSprings.standard,
      );
    }
  }

  @override
  void dispose() {
    _sel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: widget.onTap,
      scaleTo: 0.93,
      enableTilt: false, // 작은 알약이라 틸트 대신 스케일 피드백만
      borderRadius: BorderRadius.circular(100),
      child: AnimatedBuilder(
        animation: _sel,
        builder: (context, _) {
          final raw = _sel.value; // bounce 로 1 을 살짝 넘겼다 안착(팝)
          final t = raw.clamp(0.0, 1.0);
          final bg = Color.lerp(context.colors.surface, _catAccent, t)!;
          final border = Color.lerp(context.colors.border, _catAccent, t)!;
          final fg = Color.lerp(context.colors.textPrimary, Colors.white, t)!;
          final iconColor = Color.lerp(_catAccent, Colors.white, t)!;
          return Transform.scale(
            scale: 1 + 0.06 * raw, // 선택 시 살짝 커지며 오버슈트
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: border, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 15, color: iconColor),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    this.focusNode,
    required this.onSubmitted,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    // 공용 검색창(사용자 검색 디자인 기준)으로 위임 — 세 검색창 디자인 통일.
    return AppSearchField(
      controller: controller,
      focusNode: focusNode,
      hintText: '시설·장소 검색...',
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onClear: onClear,
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
      color: context.colors.surface,
      shape: CircleBorder(
        side: BorderSide(color: context.colors.border, width: 0.5),
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
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(
                        context.colors.primaryDark,
                      ),
                    ),
                  )
                : Icon(
                    Icons.my_location,
                    color: context.colors.primaryDark,
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }
}
