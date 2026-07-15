import '../data/mock_data.dart' show MockPet;

/// 내정보 화면용 집계 데이터.
class ProfileData {
  final String nickname;
  final String username;
  final String userType;
  final String? profileImageUrl;

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

  // 업체 인증(0025) — 승인 여부는 모드와 무관한 신뢰 정보, 상호는 업체 모드일 때만 옴.
  final bool isBusiness;
  final String? businessName;

  /// 현재 계정 모드 ('personal' | 'business') — 업체 모드 프로필 분리 표시에 사용.
  final String activeMode;

  /// 업체 얼굴 사진(대표 사진) — 업체 모드 내정보 히어로에 사용(개인 사진과 분리).
  final String? businessPhotoUrl;

  const ProfileData({
    required this.nickname,
    required this.username,
    required this.userType,
    this.profileImageUrl,
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
    this.isBusiness = false,
    this.businessName,
    this.activeMode = 'personal',
    this.businessPhotoUrl,
  });

  /// 표시용 동네명(행정동) — address 의 마지막 토큰. 미인증이면 null.
  String? get regionName =>
      regionNameFromAddress(address, verified: isLocationVerified);

  /// address("경기 화성시 동탄2동") → 동네명("동탄2동"). 미인증/빈값이면 null.
  /// 프로필 편집 화면 등 ProfileData 인스턴스 없이도 쓰도록 정적 제공.
  static String? regionNameFromAddress(
    String? address, {
    required bool verified,
  }) {
    if (!verified || address == null || address.trim().isEmpty) return null;
    final parts = address.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? null : parts.last;
  }
}

/// 받은 평가 태그 집계 1건 (review_category_counts).
class ReviewTag {
  final String category; // 예: '친절해요'
  final int count;
  const ReviewTag({required this.category, required this.count});
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

  // 업체 인증(0025) — 공개 뷰 노출. 상호·사업장 정보는 승인 업체면 상시 공개
  // (0026 §2 개정 — 주인 모드와 무관, 얼굴 선택은 진입 맥락이 담당).
  final bool isBusiness;
  final String? businessName;
  final String? businessCategory;
  final String? businessAddress;
  final String? businessPhone;
  final String? businessFacilityId; // 매칭 시설 — 방문 후기 조회용
  final String? businessPhotoUrl; // 업체 얼굴 사진(대표 사진) — 개인 사진과 분리

  /// 승인 업체 얼굴이 존재하는가 — 실제 표시는 forcePersonalFace(진입 맥락)와 조합.
  bool get isBusinessMode => businessName != null;

  final int reviewCount; // 받은 평가
  final int pawingCount; // 그 사용자가 팔로우
  final int pawmateCount; // 그 사용자를 팔로우
  final int postCount; // 게시글 수

  final List<MockPet> pets;
  final List<ReviewTag> reviewTags; // 받은 평가 태그 집계(많은 순)

  const PublicProfileData({
    required this.userId,
    required this.nickname,
    required this.userType,
    this.profileImageUrl,
    this.address,
    this.isLocationVerified = false,
    this.isBusiness = false,
    this.businessName,
    this.businessCategory,
    this.businessAddress,
    this.businessPhone,
    this.businessFacilityId,
    this.businessPhotoUrl,
    required this.reviewCount,
    required this.pawingCount,
    required this.pawmateCount,
    required this.postCount,
    required this.pets,
    this.reviewTags = const [],
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
