/// 시설 후기 1건 (facility_reviews_of RPC 기준).
class FacilityReview {
  final String id;
  final String facilityId;
  final String userId;
  final String authorNickname;
  final int rating; // 1~5
  final String? content;
  final List<String> photoUrls;
  final DateTime createdAt;
  final bool isMine;

  /// 같은 사용자의 몇 번째 방문 후기인지(1부터) — 복수 후기 허용에 따른 순번.
  final int? visitNo;

  const FacilityReview({
    required this.id,
    this.facilityId = '',
    required this.userId,
    required this.authorNickname,
    required this.rating,
    required this.content,
    required this.photoUrls,
    required this.createdAt,
    required this.isMine,
    this.visitNo,
  });

  factory FacilityReview.fromJson(Map<String, dynamic> j) => FacilityReview(
    id: j['id'] as String,
    facilityId: (j['facility_id'] ?? '') as String,
    userId: (j['user_id'] ?? '') as String,
    authorNickname: (j['author_nickname'] ?? '알 수 없음') as String,
    rating: (j['rating'] as num?)?.toInt() ?? 0,
    content: j['content'] as String?,
    photoUrls: [
      for (final u in (j['photo_urls'] as List? ?? const [])) u as String,
    ],
    createdAt:
        DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal() ??
        DateTime.now(),
    isMine: j['is_mine'] == true,
    visitNo: (j['visit_no'] as num?)?.toInt(),
  );
}
