import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_colors.dart';
import '../../models/community.dart';
import '../../services/facility_repository.dart';
import '../../services/community_repository.dart';
import '../../services/location_service.dart';
import '../../widgets/post_card.dart';
import '../../widgets/facility_sheet.dart';
import '../../widgets/map_bottom_sheet.dart';
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

class _MapTabState extends State<MapTab>
    with AutomaticKeepAliveClientMixin {
  // pmdb 0023: 맵은 앱에 1개만 두고 살려둔다. 스왑(상세 표시)으로 잠시 빌드가 빠져도
  // 탭 상태(_detailFacility/_lastCamera 등)는 keep-alive 로 유지.
  @override
  bool get wantKeepAlive => true;

  NaverMapController? _controller;
  final _searchController = TextEditingController();
  bool _locating = false;
  bool _loadingFac = false;

  // 지도 위에 라우트·모달을 올리면 PlatformView 충돌로 본문이 깨진다(pmdart #28).
  // 그래서 showSheetOverMap: 지도를 스냅샷으로 얼린 뒤(_mapSnapshot) 그 위에 커스텀
  // 바텀시트(_sheetChild)를 올린다(라이브 지도는 트리에서 빠짐).
  File? _mapSnapshot;
  Widget? _sheetChild;
  // 동네 게시글은 전용 화면 스왑(_detailCluster).
  PostCluster? _detailCluster;
  // 스왑/시트 후 지도 재생성 시 직전 카메라로 복원(현재위치 점프 방지).
  NCameraPosition? _lastCamera;

  // 선택된 카테고리(기본 전체). 마커 id → Facility(탭 시 바텀시트용).
  // 카테고리는 단일 선택(한 번에 하나만 표시) — 사업 카테고리가 겹치기 때문.
  final Set<String> _selected = {'animal_hospital'};
  final Map<String, Facility> _byMarkerId = {};
  final Map<String, NOverlayImage?> _catIcons = {}; // 카테고리별 마커 아이콘 캐시
  final Map<String, PostCluster> _clusterByMarkerId = {}; // 게시글 클러스터 마커
  bool _dongSynced = false; // 세션당 1회 행정동 centroid 보충
  NLatLng? _loadedCenter; // 마지막 조회 중심(디바운스 기준)

  Facility? _searchResult; // 검색으로 선택된 시설(강조 마커, 재조회에도 유지)
  List<Facility> _suggestions = const []; // 자동완성 후보
  Timer? _suggestDebounce;

  // 네이버 지도 커스텀 스타일(지도 스타일 에디터에서 발급한 ID).
  static const _customStyleId = '430d08d6-8afd-4661-9ffe-bcbf5c4351f4';
  static const _defaultZoom = 14.0;
  static const _seoul = NLatLng(37.5666, 126.9784);
  static const _initialPosition =
      NCameraPosition(target: _seoul, zoom: _defaultZoom);

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// 반경 5km 시설 조회 → 마커 갱신.
  Future<void> _loadFacilities(NLatLng center) async {
    final c = _controller;
    if (c == null) return;
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
      for (final f in rows) {
        final id = 'fac_${f.id}';
        final icon = await _iconFor(f.category); // 카테고리 PNG 아이콘(캐시)
        final m = NMarker(id: id, position: NLatLng(f.lat, f.lng), icon: icon)
          ..setIsHideCollidedMarkers(true)
          ..setCaption(NOverlayCaption(
            text: _wrapCaption(f.name),
            textSize: 11,
            color: AppColors.textPrimary,
            haloColor: Colors.white,
          ))
          ..setIsHideCollidedCaptions(true)
          ..setOnTapListener((_) => _showFacilitySheet(f));
        if (icon != null) {
          m.setAnchor(const NPoint(0.5, 0.5)); // 원형 아이콘 → 중앙 앵커
        } else {
          m.setIconTintColor(_colorFor(f.category)); // 아이콘 로드 실패 시 폴백
        }
        _byMarkerId[id] = f;
        markers.add(m);
      }
      for (final cl in clusters) {
        final id = 'cluster_${cl.regionCode}';
        // 동 중심에 게시글 수 배지(탭 시 그 동 게시글 목록). 없으면 캡션 폴백.
        final badge = await _clusterBadge(cl.count);
        final m = NMarker(id: id, position: NLatLng(cl.lat, cl.lng), icon: badge)
          ..setAnchor(const NPoint(0.5, 0.5))
          ..setOnTapListener((_) => _showRegionPosts(cl));
        if (badge == null) {
          m.setCaption(NOverlayCaption(
            text: '게시글 ${cl.count}',
            color: _postsLayer.$3,
            haloColor: Colors.white,
          ));
        }
        _clusterByMarkerId[id] = cl;
        markers.add(m);
      }
      // 검색으로 선택된 시설 강조 마커(카테고리/반경과 무관하게 항상 표시).
      final sr = _searchResult;
      if (sr != null) {
        markers.add(NMarker(id: 'search', position: NLatLng(sr.lat, sr.lng))
          ..setIconTintColor(AppColors.primaryDark)
          ..setGlobalZIndex(1000000)
          ..setCaption(NOverlayCaption(
            text: _wrapCaption(sr.name),
            textSize: 13,
            color: AppColors.primaryDark,
            haloColor: Colors.white,
          ))
          ..setOnTapListener((_) => _showFacilitySheet(sr)));
      }
      if (markers.isNotEmpty) await c.addOverlayAll(markers);
      _loadedCenter = center;
    } catch (_) {
      // 오류가 나도 이전 마커는 제거(선택 해제한 카테고리 마커가 남지 않도록).
      try {
        await c.clearOverlays(type: NOverlayType.marker);
      } catch (_) {/* 무시 */}
      _byMarkerId.clear();
      _clusterByMarkerId.clear();
      if (mounted) {
        final msg = _selected.contains(_postsLayer.$1) && _selected.length == 1
            ? '게시글을 불러오지 못했어요'
            : '주변 시설을 불러오지 못했어요';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
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
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.0)),
              const Text('게시글',
                  style: TextStyle(
                      color: Colors.white, fontSize: 9, height: 1.3)),
            ],
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// 클러스터 탭 → 그 행정동 게시글 목록(지도 대신 탭 내 스왑으로 표시).
  void _showRegionPosts(PostCluster cl) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _detailCluster = cl);
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
    // 주의: 여기서 unfocus 하면 검색창 탭 → 키보드가 뜰 때의 지도 리레이아웃이
    // onCameraIdle 을 유발해 키보드가 바로 닫힌다. 키보드 해제는 onMapTapped/배리어가 담당.
    final c = _controller;
    if (c == null || _loadedCenter == null || _loadingFac) return;
    final cam = await c.getCameraPosition();
    _lastCamera = cam; // 스왑 후 복원용
    final moved = Geolocator.distanceBetween(
      _loadedCenter!.latitude, _loadedCenter!.longitude,
      cam.target.latitude, cam.target.longitude,
    );
    if (moved > 1000) await _loadFacilities(cam.target);
  }

  // 카테고리 단일 선택(게시글 포함 한 번에 하나만). 같은 칩을 다시 누르면 해제.
  void _toggleCategory(String code) {
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
  Future<NOverlayImage?> _iconFor(String category) async {
    if (_catIcons.containsKey(category)) return _catIcons[category];
    NOverlayImage? out;
    try {
      out = await _renderMarkerIcon(category);
    } catch (_) {
      out = null;
    }
    _catIcons[category] = out;
    return out;
  }

  static const _markerAssets = <String, String>{
    'animal_hospital': 'assets/images/hospital.png',
    'grooming': 'assets/images/scissors.png',
    'pet_hotel': 'assets/images/school.png',
    'pet_cafe': 'assets/images/cup-soda.png',
    'pet_sales': 'assets/images/IMG_4.png',
  };

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
        minX.toDouble(), minY.toDouble(), (maxX + 1).toDouble(), (maxY + 1).toDouble());
  }

  Future<NOverlayImage?> _renderMarkerIcon(String category) async {
    final asset = _markerAssets[category];
    if (asset == null) return null;
    const target = 96.0;
    final color = _colorFor(category);
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final img = frame.image;
    // 투명 여백 제거: 불투명 픽셀의 경계상자(없으면 전체). IMG_4 처럼 여백이 큰
    // 이미지가 작게 보이는 문제 해결.
    final src = await _opaqueBounds(img);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const c = target / 2;
    canvas.drawCircle(const Offset(c, c), c - 1, Paint()..color = Colors.white);
    canvas.drawCircle(
        const Offset(c, c),
        c - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = color);
    // 잘라낸 아이콘을 원 안에 contain 으로 배치.
    final box = target * 0.6;
    final s = box / (src.width > src.height ? src.width : src.height);
    final dw = src.width * s, dh = src.height * s;
    final dx = (target - dw) / 2, dy = (target - dh) / 2;
    canvas.drawImageRect(
      img,
      src,
      Rect.fromLTWH(dx, dy, dw, dh),
      Paint()..filterQuality = FilterQuality.high,
    );
    img.dispose();

    final image =
        await recorder.endRecording().toImage(target.toInt(), target.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    return NOverlayImage.fromByteArray(bytes.buffer.asUint8List());
  }

  /// 게시글 레이어를 켤 때, 현재 화면에 조회된 게시글이 없으면 안내.
  Future<void> _loadPostsAndNotify(NLatLng center) async {
    await _loadFacilities(center);
    if (mounted &&
        _selected.contains(_postsLayer.$1) &&
        _clusterByMarkerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 지역에 조회된 게시글이 없어요')),
      );
    }
  }

  /// 시설 상세(정보 + 후기/사진 + 후기 작성 + 네이버 지도 링크) — 지도 위 바텀시트.
  void _showFacilitySheet(Facility f) {
    showSheetOverMap(FacilityDetailContent(
      facility: f,
      color: _colorFor(f.category),
      label: kFacilityLabels[f.category] ?? f.category,
    ));
  }

  /// 지도 위에 안전하게 바텀시트를 띄운다(재사용): 라이브 지도를 스냅샷으로 얼린 뒤
  /// 그 위에 [MapBottomSheet] 로 [content] 를 올린다(PlatformView 충돌 회피, #28).
  /// content 는 너비-안전 위젯만(머티리얼 버튼/Spacer/Expanded 금지).
  Future<void> showSheetOverMap(Widget content) async {
    FocusManager.instance.primaryFocus?.unfocus();
    File? snap;
    try {
      snap = await _controller?.takeSnapshot();
    } catch (_) {/* 스냅샷 실패 시 회색 배경으로 폴백 */}
    if (!mounted) return;
    setState(() {
      _mapSnapshot = snap;
      _sheetChild = content;
    });
  }

  void _closeSheetOverMap() {
    setState(() {
      _sheetChild = null;
      _mapSnapshot = null;
    });
    // 지도 위젯이 다시 빌드되며 재생성됨 → onMapReady 에서 _lastCamera 로 복원.
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
    } catch (_) {/* 빈 결과 처리 */}
    if (!mounted) return;
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$q" 검색 결과가 없어요')),
      );
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
          FacilityRepository.instance
              .searchByName(q, lat: center?.latitude, lng: center?.longitude),
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
      } catch (_) {/* 빈 결과 */}
      if (!mounted || _searchController.text.trim() != q) return;
      setState(() => _suggestions = merged.take(6).toList());
    });
  }

  void _clearSearch() {
    _suggestDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _suggestions = const [];
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
    });
    _searchController.text = f.name;
    FocusManager.instance.primaryFocus?.unfocus();
    await c.updateCamera(
      NCameraUpdate.scrollAndZoomTo(target: NLatLng(f.lat, f.lng), zoom: 16)
        ..setAnimation(
            animation: NCameraAnimation.easing,
            duration: const Duration(milliseconds: 400)),
    );
    // 카메라 이동 → onCameraIdle 가 마커 재로드(강조 마커 포함). 상세 즉시 표시.
    if (mounted) _showFacilitySheet(f);
  }

  /// 자동완성 후보 드롭다운.
  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) {
          final f = _suggestions[i];
          final dist = f.distanceM <= 0
              ? ''
              : (f.distanceM < 1000
                  ? '${f.distanceM.round()}m'
                  : '${(f.distanceM / 1000).toStringAsFixed(1)}km');
          return InkWell(
            onTap: () => _goToFacility(f),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _colorFor(f.category)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        if (f.address != null && f.address!.isNotEmpty)
                          Text(f.address!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  if (dist.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(dist,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textTertiary)),
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

    // 지도 위 바텀시트: 라이브 지도 대신 스냅샷 이미지 + MapBottomSheet 를 그린다
    // (PlatformView 위 모달 충돌 회피, pmdart #28).
    if (_sheetChild != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeSheetOverMap();
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              if (_mapSnapshot != null)
                Positioned.fill(
                  child: Image.file(_mapSnapshot!, fit: BoxFit.cover),
                )
              else
                const Positioned.fill(
                    child: ColoredBox(color: Color(0xFFEAEAEA))),
              Positioned.fill(
                child: MapBottomSheet(
                  onClose: _closeSheetOverMap,
                  child: _sheetChild!,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 동네 게시글: 전용 화면 스왑(지도 트리에서 제거).
    if (_detailCluster != null) {
      final cl = _detailCluster!;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _detailCluster = null);
        },
        child: _RegionPostsScreen(
          cluster: cl,
          onClose: () => setState(() => _detailCluster = null),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          ClipRect(
            child: NaverMap(
              options: NaverMapViewOptions(
                // 스왑 복귀 시 직전 카메라로 복원(없으면 첫 진입 기본 위치).
                initialCameraPosition: _lastCamera ?? _initialPosition,
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
                      onChanged: _onSuggestChanged,
                      onClear: _clearSearch,
                    ),
                    if (_suggestions.isNotEmpty) _buildSuggestions(),
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
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    required this.onSubmitted,
    required this.onChanged,
    required this.onClear,
  });

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
              onChanged: onChanged,
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
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: onClear,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.close,
                          color: AppColors.textTertiary, size: 20),
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

/// 동네 게시글 목록 화면(클러스터 탭 → 그 동에서 작성된 게시글).
class _RegionPostsScreen extends StatelessWidget {
  final PostCluster cluster;
  final VoidCallback onClose;
  const _RegionPostsScreen({required this.cluster, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading:
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: onClose),
        title: Text('이 동네 게시글 ${cluster.count}개'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Post>>(
          future: CommunityRepository.instance.fetchPostsByIds(cluster.postIds),
          builder: (ctx, snap) {
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
            // 이 화면도 탭 내 스왑(#28). Align 이 제약을 loosen → SizedBox 로 폭을
            // 화면폭으로 고정 → 그 안 ListView(스크롤) 정상. PostCard 는 유한 폭을 받아
            // 내부 Spacer/double.infinity 가 정상 동작.
            final w = MediaQuery.of(context).size.width;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: w,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: posts.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: PostCard(
                      post: posts[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PostDetailScreen(post: posts[i])),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
