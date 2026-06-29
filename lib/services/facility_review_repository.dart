import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/facility_review.dart';
import 'session.dart';

/// 시설 후기 조회/작성/삭제. 시설당 1인 1후기(upsert).
class FacilityReviewRepository {
  FacilityReviewRepository._();
  static final FacilityReviewRepository instance =
      FacilityReviewRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String? get _uid => SessionManager.instance.user?.id;

  /// 시설의 후기 목록(최신순).
  Future<List<FacilityReview>> fetchReviews(String facilityId) async {
    final rows = await _c
        .from('v_facility_reviews')
        .select()
        .eq('facility_id', facilityId)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((r) => FacilityReview.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 후기 작성/수정(시설당 1인 1건 upsert).
  Future<void> submit({
    required String facilityId,
    required int rating,
    String? content,
    List<String> photoUrls = const [],
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('로그인이 필요합니다');
    final c = (content ?? '').trim();
    await _c.from('facility_reviews').upsert({
      'facility_id': facilityId,
      'user_id': uid,
      'rating': rating,
      'content': c.isEmpty ? null : c,
      'photo_urls': photoUrls,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'facility_id,user_id');
  }

  /// 내 후기 삭제.
  Future<void> deleteMine(String facilityId) async {
    final uid = _uid;
    if (uid == null) throw StateError('로그인이 필요합니다');
    await _c
        .from('facility_reviews')
        .delete()
        .eq('facility_id', facilityId)
        .eq('user_id', uid);
  }
}
