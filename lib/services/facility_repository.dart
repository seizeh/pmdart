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
  final String source; // localdata | naver
  final double avgRating; // 평균 별점(캐시, 0이면 후기 없음/미승격)
  final int reviewCount;

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
    this.source = 'localdata',
    this.avgRating = 0,
    this.reviewCount = 0,
  });

  bool get isNaver => source == 'naver';

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
        source: (j['source'] ?? 'localdata') as String,
        avgRating: (j['avg_rating'] as num?)?.toDouble() ?? 0,
        reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
      );
}

/// 분양업(pet_sales) 신뢰도 등급. 사업자 업종만 '반려동물판매업'으로 등록하고
/// 실제론 분양과 무관한 업장이 섞여 있어, 상호명 키워드로 추정해 사용자에게 알린다.
enum PetSalesTrust { likely, unclear, caution }

/// 분양 신뢰도 평가 결과(점수 + 등급 + 근거 키워드).
class PetSalesScore {
  final int score; // 가점 - 감점
  final PetSalesTrust level;
  final List<String> positives; // 매칭된 가점 단어(근거 표시용)
  final List<String> negatives; // 매칭된 감점 단어
  const PetSalesScore({
    required this.score,
    required this.level,
    required this.positives,
    required this.negatives,
  });
}

// 분양 전문점에 흔한 단어(가점) / 도매·법인·용품점 등 비분양에 흔한 단어(감점).
// '캐터리'·'켄넬샵' 등은 '캐터'·'켄넬'에 부분일치로 포함된다.
const _salesPositiveWords = ['분양', '켄넬', '캐터', '브리더', '브리딩'];
const _salesNegativeWords = [
  '(주)', '㈜', '주식회사', '컴퍼니', '홀딩스', '용품', 'company', 'holdings'
];

// 예외 화이트리스트: 상호에 (주) 등 감점 단어가 있어도 실제 분양 전문 브랜드/체인은
// 무조건 '신뢰'로 본다(예: (주)도그마루). 부분일치라 '캣플'→'캣플헤븐'도 포함.
// 전국 등장 빈도(≥4회) 자동 후보 중 분양 전문 체인만 선별해 반영(마트·수족관·법인 제외).
// 새 브랜드는 여기 한 줄 추가하면 된다.
const _salesWhitelist = [
  // 직접 지정
  '도그마루', '밀레펫', '미유펫', '도그짱', '도그플러스', '펫하우스', '펫랜드',
  // 빈도 기반 선별(강아지·고양이 분양 체인)
  '야옹아', '버디독', '라이프독', '드림독', '퍼피하우스', '해피애견타운',
  '똥강아지', '나라애견', '강아지나라', '낭만고양이', '캣플', '블리독',
  '몽냥몽냥', '꽁냥꽁냥', '미오즈', '다온', '베이비몽', '펫퍼스트', '이츠펫',
  '코리아펫', '미니펫', '더펫', '마이펫', '유앤미펫', '와우펫앤쥬', '펫엔글라이더',
  '그린프레밀리',
];

/// 분양업 상호의 신뢰도 점수화. pet_sales 가 아니면 null(평가 안 함).
PetSalesScore? evaluatePetSales(Facility f) {
  if (f.category != 'pet_sales') return null;
  final name = f.name;
  final lower = name.toLowerCase();
  final pos = [for (final w in _salesPositiveWords) if (name.contains(w)) w];
  // 화이트리스트 브랜드면 감점 무시하고 신뢰(가점 단어와 함께 근거로 표시).
  final brand = [for (final b in _salesWhitelist) if (name.contains(b)) b];
  if (brand.isNotEmpty) {
    final positives = [...brand, ...pos];
    return PetSalesScore(
      score: positives.length,
      level: PetSalesTrust.likely,
      positives: positives,
      negatives: const [],
    );
  }
  final neg = [
    for (final w in _salesNegativeWords)
      if (name.contains(w) || lower.contains(w.toLowerCase())) w
  ];
  final score = pos.length - neg.length;
  final level = score > 0
      ? PetSalesTrust.likely
      : (score < 0 ? PetSalesTrust.caution : PetSalesTrust.unclear);
  return PetSalesScore(
      score: score, level: level, positives: pos, negatives: neg);
}

/// 분양 신뢰도가 너무 낮아(점수 ≤ -2) 지도·검색에서 숨길 시설인지.
/// 사업자만 판매업 등록하고 실제론 비분양일 가능성이 높은 경우.
bool isLowTrustHidden(Facility f) {
  final s = evaluatePetSales(f);
  return s != null && s.score <= -2;
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

  /// 시설명 검색(지도 검색창). [lat]/[lng] 주면 가까운 순 정렬. 최대 30건.
  Future<List<Facility>> searchByName(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final rows = await _c.rpc('facilities_search', params: {
      'p_query': q,
      'p_lng': lng,
      'p_lat': lat,
    });
    return (rows as List)
        .map((r) => Facility.fromJson(r as Map<String, dynamic>))
        // 분양 신뢰도가 너무 낮은(점수 ≤ -2) 비분양 추정 시설은 검색에서도 제외.
        .where((f) => !isLowTrustHidden(f))
        .toList();
  }

  /// 애견카페 실시간 검색(네이버 지역검색 프록시). 결과 최대 5건, 5km 후필터.
  /// DB 미적재(공공데이터에 전용 업종 없음) — 지도 진입 시 현재 위치로 검색.
  Future<List<Facility>> searchPetCafes({
    required double lat,
    required double lng,
    double radiusM = 10000, // 지역 한정 검색이라 구 단위로 다소 멀 수 있어 완화
    String? query, // 이름 검색 시 검색어(없으면 현재 동네 애견카페)
  }) async {
    try {
      final res = await _c.functions.invoke('search-petcafe', body: {
        'lat': lat,
        'lng': lng,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      });
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
          source: 'naver', // DB 미적재 — 후기 작성 시 ensure_naver_facility 로 승격
        ));
      }
      out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
      return out;
    } catch (_) {
      return const []; // 실시간 검색 실패는 다른 마커에 영향 없이 빈 결과
    }
  }
}
