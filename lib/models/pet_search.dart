/// 펫 검색/공개 프로필 도메인 모델.
library;

/// 펫 검색 결과 1건 (검색 탭의 '반려동물' 섹션).
class PetHit {
  final String id;
  final String name;
  final String species;
  final String? imageUrl;
  final String ownerNickname;

  const PetHit({
    required this.id,
    required this.name,
    required this.species,
    required this.imageUrl,
    required this.ownerNickname,
  });
}

/// 공개 펫 프로필 (read-only 조회용).
class PetProfile {
  final String id;
  final String name;
  final String species;
  final String? gender; // male / female / null
  final DateTime? birthDate;
  final bool isNeutered;
  final String? bio;
  final String? imageUrl;
  final String ownerId;
  final String ownerNickname;
  final bool hasAiReference; // AI 인증 기준 사진 등록 여부 (0019)
  final int matchCount; // 개체 일치 누적 횟수 (신뢰도)

  const PetProfile({
    required this.id,
    required this.name,
    required this.species,
    required this.gender,
    required this.birthDate,
    required this.isNeutered,
    required this.bio,
    required this.imageUrl,
    required this.ownerId,
    required this.ownerNickname,
    this.hasAiReference = false,
    this.matchCount = 0,
  });
}
