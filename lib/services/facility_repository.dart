import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 반려동물 시설(공공데이터) 1건. facilities_within RPC 결과 매핑 (0021).
class Facility {
  final String id;
  final String category; // animal_hospital / grooming / pet_hotel / pet_sales
  final String name;
  final String? address;
  final String? phone;
  final bool isOpen;
  final double lat;
  final double lng;
  final double distanceM;

  const Facility({
    required this.id,
    required this.category,
    required this.name,
    required this.address,
    required this.phone,
    required this.isOpen,
    required this.lat,
    required this.lng,
    required this.distanceM,
  });

  factory Facility.fromJson(Map<String, dynamic> j) => Facility(
        id: j['id'] as String,
        category: (j['category'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        address: j['address'] as String?,
        phone: j['phone'] as String?,
        isOpen: j['is_open'] == true,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        distanceM: (j['distance_m'] as num?)?.toDouble() ?? 0,
      );
}

/// 시설 카테고리 메타(라벨). DB enum 값과 1:1.
const Map<String, String> kFacilityLabels = {
  'animal_hospital': '동물병원',
  'grooming': '미용',
  'pet_hotel': '위탁·호텔',
  'pet_sales': '분양',
  'pet_cafe': '애견카페',
};

/// 현재 위치 반경 시설 조회. 좌표/반경/카테고리만 넘기고 DB가 PostGIS로 반환.
class FacilityRepository {
  FacilityRepository._();
  static final FacilityRepository instance = FacilityRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// [categories] 가 비거나 null 이면 전체. 서버가 5km 상한·500건 제한.
  Future<List<Facility>> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    List<String>? categories,
  }) async {
    final rows = await _c.rpc('facilities_within', params: {
      'p_lng': lng,
      'p_lat': lat,
      'p_radius_m': radiusM,
      'p_categories': (categories == null || categories.isEmpty) ? null : categories,
    });
    return (rows as List)
        .map((r) => Facility.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 애견카페 실시간 검색(네이버 지역검색 프록시). 결과 최대 5건, 5km 후필터.
  /// DB 미적재(공공데이터에 전용 업종 없음) — 지도 진입 시 현재 위치로 검색.
  Future<List<Facility>> searchPetCafes({
    required double lat,
    required double lng,
    double radiusM = 5000,
  }) async {
    try {
      final res = await _c.functions
          .invoke('search-petcafe', body: {'lat': lat, 'lng': lng});
      final data = (res.data as Map?) ?? const {};
      final items = (data['items'] as List?) ?? const [];
      final out = <Facility>[];
      for (final raw in items) {
        final m = raw as Map<String, dynamic>;
        final clat = (m['lat'] as num).toDouble();
        final clng = (m['lng'] as num).toDouble();
        final dist = Geolocator.distanceBetween(lat, lng, clat, clng);
        if (dist > radiusM) continue; // 5km 후필터(지역검색은 위치정렬이 약함)
        out.add(Facility(
          id: 'petcafe_${clat.toStringAsFixed(5)}_${clng.toStringAsFixed(5)}',
          category: 'pet_cafe',
          name: (m['name'] ?? '') as String,
          address: m['address'] as String?,
          phone: m['phone'] as String?,
          isOpen: true,
          lat: clat,
          lng: clng,
          distanceM: dist,
        ));
      }
      out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      return out;
    } catch (_) {
      return const []; // 실시간 검색 실패는 다른 마커에 영향 없이 빈 결과
    }
  }
}
