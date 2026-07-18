/// 소셜(팔로우) 도메인 모델.
library;

/// 사용자 연결/검색 결과 항목.
class Connection {
  final String userId;
  final String nickname;
  final String userType;

  /// Pawmate(나를 팔로우) 목록에서 내가 맞팔 중인지. 그 외 맥락에선 null.
  final bool? iFollowBack;

  /// 검색 결과 등에서 내가 이미 팔로우(Pawing) 중인지. 그 외 null.
  final bool? following;

  /// 프로필 사진 — 검색 타일 블러 배경용(없으면 null).
  final String? profileImageUrl;

  /// 업체 인증(0025) — 배지 표시용. 상호는 업체 모드 계정만 온다.
  final bool isBusiness;
  final String? businessName;

  /// 개인 얼굴 통계(검색 타일용) — 받은 후기·Pawing·Pawmate. 목록 밖 맥락엔 null.
  final int? reviewCount;
  final int? pawingCount;
  final int? pawmateCount;

  const Connection({
    required this.userId,
    required this.nickname,
    required this.userType,
    this.iFollowBack,
    this.following,
    this.profileImageUrl,
    this.isBusiness = false,
    this.businessName,
    this.reviewCount,
    this.pawingCount,
    this.pawmateCount,
  });

  factory Connection.fromJson(Map<String, dynamic> j) => Connection(
    userId: (j['user_id'] ?? j['id']) as String,
    nickname: (j['nickname'] ?? '알 수 없음') as String,
    userType: (j['user_type'] ?? '') as String,
    iFollowBack: j['i_follow_back'] as bool?,
    following: j['following'] as bool?,
    profileImageUrl: j['profile_image_url'] as String?,
    isBusiness: j['is_business'] == true,
    businessName: j['business_name'] as String?,
  );

  Connection copyWith({bool? following, bool? iFollowBack}) => Connection(
    userId: userId,
    nickname: nickname,
    userType: userType,
    profileImageUrl: profileImageUrl,
    iFollowBack: iFollowBack ?? this.iFollowBack,
    following: following ?? this.following,
    isBusiness: isBusiness,
    businessName: businessName,
    reviewCount: reviewCount,
    pawingCount: pawingCount,
    pawmateCount: pawmateCount,
  );
}
