/// 반려동물 도메인 모델 — 한 마리를 여러 보호자가 공유(N:M)할 수 있다.
library;

class Pet {
  final String id;
  final String name;
  final String species;
  final String? speciesKind; // 'dog' | 'cat' (강아지/고양이)
  final String? gender; // male / female / null
  final DateTime? birthDate;
  final String? bio;
  final String role; // owner / co_guardian (현재 사용자 기준)
  final int guardianCount;
  final String ownerName;
  final String? imageUrl;
  final bool isIdentityVerified; // AI 인증 기준 사진 등록 여부 (0019)
  final int matchCount; // 개체 일치 누적 횟수 (신뢰도)

  const Pet({
    required this.id,
    required this.name,
    required this.species,
    this.speciesKind,
    this.gender,
    this.birthDate,
    this.bio,
    this.role = 'owner',
    this.guardianCount = 1,
    this.ownerName = '',
    this.imageUrl,
    this.isIdentityVerified = false,
    this.matchCount = 0,
  });
}
