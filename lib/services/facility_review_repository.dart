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
  /// [hasIncentive] — 업체 혜택(할인·사은품)을 받고 쓰는 후기(표시광고법 표시 의무).
  /// [videos] — 첨부 영상 최대 2개(p_videos jsonb, {url, thumb_url, path}).
  Future<void> addReview({
    required String facilityId,
    required int rating,
    String? body,
    List<String> photoPaths = const [],
    List<String> photoUrls = const [],
    List<ReviewVideo> videos = const [],
    bool hasIncentive = false,
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
        'p_has_incentive': hasIncentive,
        'p_videos': [for (final v in videos) v.toJson()],
      },
    );
  }

  /// 후기 단건 조회 — 후기 댓글 알림 딥링크용. 없거나 숨김이면 null.
  Future<FacilityReview?> fetchReviewById(String reviewId) async {
    final rows = await _c.rpc(
      'facility_review_by_id',
      params: {'p_review': reviewId},
    );
    final list = rows as List;
    if (list.isEmpty) return null;
    return FacilityReview.fromJson(list.first as Map<String, dynamic>);
  }

  /// 후기 댓글 목록(오래된 순). 뷰가 업체 모드 댓글의 상호 표시를 담당한다.
  Future<List<FacilityReviewComment>> fetchComments(String reviewId) async {
    final rows = await _c
        .from('v_facility_review_comment_feed')
        .select()
        .eq('review_id', reviewId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map(
          (r) => FacilityReviewComment.fromJson(
            r as Map<String, dynamic>,
            myUserId: _uid,
          ),
        )
        .toList();
  }

  /// 후기 댓글 작성 — 후기 작성자에게 알림은 서버 트리거가 발송.
  Future<void> addComment(String reviewId, String content) async {
    final uid = _uid;
    if (uid == null) throw StateError('로그인이 필요합니다');
    await _c.from('facility_review_comments').insert({
      'review_id': reviewId,
      'user_id': uid,
      'content': content,
    });
  }

  /// 내 댓글 삭제(소프트).
  Future<void> deleteComment(String commentId) async {
    await _c
        .from('facility_review_comments')
        .update({'is_deleted': true})
        .eq('id', commentId);
  }

  /// 내 후기 삭제(소프트). [reviewId] 를 주면 그 한 건만(복수 후기), 없으면 전부.
  Future<void> deleteMine(String facilityId, {String? reviewId}) async {
    if (_uid == null) throw StateError('로그인이 필요합니다');
    await _c.rpc(
      'delete_facility_review',
      params: {'p_facility': facilityId, 'p_review': ?reviewId},
    );
  }
}
