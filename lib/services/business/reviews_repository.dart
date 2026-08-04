/// 업체가 받은 시설 후기 조회.
///
/// 쓰기는 전부 서버(apply-business 엣지 → definer RPC)가 담당하고,
/// 여기서는 본인 행 조회(RLS select-own)와 호출만 한다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/business.dart';
import '../../models/facility_review.dart' show reviewVideosFromJson;
import '../error_reporter.dart';
import 'profile_repository.dart';

class BusinessReviewsRepository {
  BusinessReviewsRepository._();
  static final BusinessReviewsRepository instance =
      BusinessReviewsRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 내 업소(매칭 시설)에 달린 후기 — 업체 프로필의 후기 관리 UI 용.
  /// 매칭 시설이 없으면(신규개업 트랙 등) 빈 목록.
  Future<List<BizFacilityReview>> fetchMyFacilityReviews() async {
    // 내 업소를 알아야 후기를 찾는다 — 프로필 역할에 물어본다(협력은 숨기지 않는다).
    final mine = await BusinessProfileRepository.instance.fetchMine();
    final fid = mine?.matchedFacilityId;
    if (fid == null) return const [];
    return fetchFacilityReviews(fid);
  }

  /// 특정 시설의 방문 후기 — 타사용자가 보는 업체 프로필에서도 사용.
  /// 지도 상세와 동일한 RPC(facility_reviews_of) 사용 — 뷰가 아니라 RPC 가 정본
  /// (존재하지 않는 v_facility_reviews 를 조회하던 버그 수정: 조용한 catch 로
  /// 빈 목록이 되어 '후기 동기화 안 됨'으로 보였다).
  Future<List<BizFacilityReview>> fetchFacilityReviews(String fid) async {
    try {
      final rows = await _c.rpc(
        'facility_reviews_of',
        params: {'p_facility': fid, 'p_limit': 50},
      );
      return [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          BizFacilityReview(
            id: (r['id'] as String?) ?? '',
            authorUserId: (r['user_id'] as String?) ?? '',
            authorNickname: (r['author_nickname'] as String?) ?? '알 수 없음',
            rating: (r['rating'] as num?)?.toInt() ?? 0,
            content: r['content'] as String?,
            createdAt: DateTime.tryParse(
              r['created_at'] as String? ?? '',
            )?.toLocal(),
            photoUrls: [
              for (final u in (r['photo_urls'] as List? ?? const []))
                u as String,
            ],
            videos: reviewVideosFromJson(r['videos']),
            visitNo: (r['visit_no'] as num?)?.toInt(),
            hasIncentive: r['has_incentive'] == true,
            isMine: r['is_mine'] == true,
          ),
      ];
    } catch (e, st) {
      // 빈 목록은 '후기 없음' 으로 보인다 — 업체가 받은 후기가 통째로 안 보인다.
      ErrorReporter.report(
        e,
        where: 'business.fetchFacilityReviews',
        stackTrace: st,
      );
      return const [];
    }
  }
}
