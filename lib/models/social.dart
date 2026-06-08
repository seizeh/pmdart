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

  const Connection({
    required this.userId,
    required this.nickname,
    required this.userType,
    this.iFollowBack,
    this.following,
  });

  factory Connection.fromJson(Map<String, dynamic> j) => Connection(
        userId: (j['user_id'] ?? j['id']) as String,
        nickname: (j['nickname'] ?? '알 수 없음') as String,
        userType: (j['user_type'] ?? '') as String,
        iFollowBack: j['i_follow_back'] as bool?,
        following: j['following'] as bool?,
      );

  Connection copyWith({bool? following, bool? iFollowBack}) => Connection(
        userId: userId,
        nickname: nickname,
        userType: userType,
        iFollowBack: iFollowBack ?? this.iFollowBack,
        following: following ?? this.following,
      );
}
