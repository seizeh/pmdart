import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/facility_review.dart';
import 'session.dart';

/// 시설 후기 (0022) — 모든 쓰기는 SECURITY DEFINER RPC 경유.
/// 애견카페는 DB row 가 없어, 후기 작성 직전 ensure_naver_facility 로 승격한다.
class FacilityReviewRepository {
  FacilityReviewRepository._();
  static final FacilityReviewRepository instance = FacilityReviewRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String? get _uid => SessionManager.instance.user?.id;

  /// 네이버 카페의 facility_id 해석(없으면 null, 생성 안 함) — 조회용.
  Future<String?> naverFacilityId(String name, String? address) async {
    final r = await _c.rpc(
      'naver_facility_id',
      params: {'p_name': name, 'p_address': address},
    );
    return r as String?;
  }

  /// 카페 승격(없으면 생성) → facility_id. 작성 직전 사용.
  Future<String> ensureNaverFacility({
    required String name,
    String? address,
    String? phone,
    required double lng,
    required double lat,
  }) async {
    final r = await _c.rpc(
      'ensure_naver_facility',
      params: {
        'p_name': name,
        'p_address': address,
        'p_phone': phone,
        'p_lng': lng,
        'p_lat': lat,
      },
    );
    return r as String;
  }

  /// 시설 후기 목록(최신순).
  Future<List<FacilityReview>> fetchReviews(String facilityId) async {
    final rows = await _c.rpc(
      'facility_reviews_of',
      params: {'p_facility': facilityId, 'p_limit': 50},
    );
    return (rows as List)
        .map((r) => FacilityReview.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 후기 작성/수정(1인 1시설 1후기 upsert).
  Future<void> addReview({
    required String facilityId,
    required int rating,
    String? body,
    List<String> photoPaths = const [],
    List<String> photoUrls = const [],
  }) async {
    if (_uid == null) throw StateError('로그인이 필요합니다');
    final b = (body ?? '').trim();
    await _c.rpc(
      'add_facility_review',
      params: {
        'p_facility': facilityId,
        'p_rating': rating,
        'p_body': b.isEmpty ? null : b,
        'p_paths': photoPaths,
        'p_urls': photoUrls,
      },
    );
  }

  /// 내 후기 삭제(소프트).
  Future<void> deleteMine(String facilityId) async {
    if (_uid == null) throw StateError('로그인이 필요합니다');
    await _c.rpc('delete_facility_review', params: {'p_facility': facilityId});
  }
}
