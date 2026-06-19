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
