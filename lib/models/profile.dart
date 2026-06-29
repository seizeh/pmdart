import '../data/mock_data.dart' show MockPet;

/// 내정보 화면용 집계 데이터.
class ProfileData {
  final String nickname;
  final String username;
  final String userType;

  final int reviewCount; // 받은 평가
  final int pawingCount; // 내가 팔로우 (Pawing)
  final int pawmateCount; // 나를 팔로우 (Pawmate)
  final int postCount; // 내 게시글
  final int heartCount; // 하트한 게시글
  final int applicationCount; // 내 지원 내역
  final int appointmentCount; // 진행 중 약속

  final List<MockPet> pets;

  // 활동 지역(동네 인증) — 0017.
  final String? address; // 예: "경기 화성시 동탄2동" (미인증이면 null)
  final bool isLocationVerified;
  final int? activityRadiusM; // 활동 범위(인증 동 기준 반경, 0.5~7km). 미설정이면 null.

  const ProfileData({
    required this.nickname,
    required this.username,
    required this.userType,
    required this.reviewCount,
    required this.pawingCount,
    required this.pawmateCount,
    required this.postCount,
    required this.heartCount,
    required this.applicationCount,
    required this.appointmentCount,
    required this.pets,
    this.address,
    this.isLocationVerified = false,
    this.activityRadiusM,
  });

  /// 표시용 동네명(행정동) — address 의 마지막 토큰. 미인증이면 null.
  String? get regionName =>
      regionNameFromAddress(address, verified: isLocationVerified);

  /// address("경기 화성시 동탄2동") → 동네명("동탄2동"). 미인증/빈값이면 null.
  /// 프로필 편집 화면 등 ProfileData 인스턴스 없이도 쓰도록 정적 제공.
  static String? regionNameFromAddress(String? address,
      {required bool verified}) {
    if (!verified || address == null || address.trim().isEmpty) return null;
    final parts = address.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? null : parts.last;
  }
}

/// 타 사용자 공개 프로필 조회용 데이터 (사용자 검색 → 프로필).
class PublicProfileData {
  final String userId;
  final String nickname;
  final String userType;
  final String? profileImageUrl;

  // 활동 지역(동네 인증) — 공개 뷰가 노출. 미인증이면 표시 안 함.
  final String? address;
  final bool isLocationVerified;

  final int reviewCount; // 받은 평가
  final int pawingCount; // 그 사용자가 팔로우
  final int pawmateCount; // 그 사용자를 팔로우
  final int postCount; // 게시글 수

  final List<MockPet> pets;

  const PublicProfileData({
    required this.userId,
    required this.nickname,
    required this.userType,
    this.profileImageUrl,
    this.address,
    this.isLocationVerified = false,
    required this.reviewCount,
    required this.pawingCount,
    required this.pawmateCount,
    required this.postCount,
    required this.pets,
  });

  /// 표시용 동네명(행정동) — address 의 마지막 토큰. 미인증이면 null.
  String? get regionName {
    if (!isLocationVerified || address == null || address!.trim().isEmpty) {
      return null;
    }
    final parts = address!.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? null : parts.last;
  }
}
