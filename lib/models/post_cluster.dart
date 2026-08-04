/// 지도 클러스터 — 종전에는 community_repository.dart 안에 있었다.
library;

/// 행정동별 게시글 클러스터(지도용). posts_by_region RPC 결과 (0021 §6).
class PostCluster {
  final String regionCode;
  final int count;
  final double lat;
  final double lng;
  final List<String> postIds;

  const PostCluster({
    required this.regionCode,
    required this.count,
    required this.lat,
    required this.lng,
    required this.postIds,
  });

  factory PostCluster.fromJson(Map<String, dynamic> j) => PostCluster(
    regionCode: (j['region_code'] ?? '') as String,
    count: (j['post_count'] as num?)?.toInt() ?? 0,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    postIds: [
      for (final id in (j['post_ids'] as List? ?? const [])) id as String,
    ],
  );
}
