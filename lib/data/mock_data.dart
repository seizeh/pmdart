/// 화면 개발용 목 데이터 모델 및 샘플.
/// 실제 Supabase 연동 전까지 UI를 구성하기 위한 임시 데이터다.
library;

/// 사용자
class MockUser {
  final String id;
  final String username;
  final String nickname;
  final String userType; // pet_owner / no_pet / business / admin
  final int reviewCount;

  const MockUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.userType,
    this.reviewCount = 0,
  });
}

/// 반려동물 — 한 마리를 여러 보호자가 공유(N:M)할 수 있다.
class MockPet {
  final String id;
  final String name;
  final String species;
  final String? gender; // male / female / null
  final DateTime? birthDate;
  final String? bio;
  final String role; // owner / co_guardian (현재 사용자 기준)
  final int guardianCount;
  final String ownerName;
  final bool isNeutered;
  final String? imageUrl;
  final bool hasAiReference; // AI 인증 기준 사진 등록 여부 (0019)
  final int matchCount; // 개체 일치 누적 횟수 (신뢰도)

  const MockPet({
    required this.id,
    required this.name,
    required this.species,
    this.gender,
    this.birthDate,
    this.bio,
    this.role = 'owner',
    this.guardianCount = 1,
    this.ownerName = '',
    this.isNeutered = false,
    this.imageUrl,
    this.hasAiReference = false,
    this.matchCount = 0,
  });
}

/// 커뮤니티 게시글
class MockPost {
  final String id;
  final String category; // walk_together / walk_proxy / care / give_away / adoption / free
  final String title;
  final String content;
  final String authorNickname;
  final String authorUserType;
  final DateTime createdAt;
  final int heartCount;
  final int commentCount;
  final DateTime? scheduledAt;
  final String? location;
  final bool hearted;

  const MockPost({
    required this.id,
    required this.category,
    required this.title,
    required this.content,
    required this.authorNickname,
    this.authorUserType = 'pet_owner',
    required this.createdAt,
    this.heartCount = 0,
    this.commentCount = 0,
    this.scheduledAt,
    this.location,
    this.hearted = false,
  });
}

/// 채팅방
class MockChatRoom {
  final String id;
  final String otherNickname;
  final String lastMessage;
  final DateTime lastAt;
  final int unreadCount;
  final String? postTitle;

  const MockChatRoom({
    required this.id,
    required this.otherNickname,
    required this.lastMessage,
    required this.lastAt,
    this.unreadCount = 0,
    this.postTitle,
  });
}

/// 정적 샘플 데이터 모음.
class MockData {
  MockData._();

  static final DateTime _now = DateTime(2026, 6, 7, 14, 0);

  static const MockUser me = MockUser(
    id: 'u_me',
    username: 'woojin_99',
    nickname: '우진',
    userType: 'pet_owner',
    reviewCount: 12,
  );

  static final List<MockPet> pets = [
    MockPet(
      id: 'p1',
      name: '콩이',
      species: '말티즈',
      gender: 'female',
      birthDate: DateTime(2021, 3, 14),
      bio: '사람을 정말 좋아하는 4살 말티즈예요. 산책할 때 다른 강아지도 잘 따라요!',
      role: 'owner',
      guardianCount: 2,
      ownerName: '우진',
    ),
    MockPet(
      id: 'p2',
      name: '바둑이',
      species: '진돗개',
      gender: 'male',
      birthDate: DateTime(2019, 8, 2),
      bio: '듬직한 진돗개. 산책 메이트를 찾고 있어요.',
      role: 'co_guardian',
      guardianCount: 3,
      ownerName: '주인장',
    ),
  ];

  static final List<MockPost> posts = [
    MockPost(
      id: 'post1',
      category: 'walk_together',
      title: '동탄2동 저녁 산책 메이트 구해요',
      content: '매일 저녁 7시쯤 호수공원에서 산책해요. 비슷한 시간대에 함께 걸으실 분 있나요? 우리 콩이는 순둥이라 다른 강아지랑도 잘 지내요!',
      authorNickname: '우진',
      authorUserType: 'pet_owner',
      createdAt: _now.subtract(const Duration(hours: 2)),
      heartCount: 14,
      commentCount: 5,
      scheduledAt: _now.add(const Duration(days: 1, hours: 5)),
      location: '동탄2동 호수공원',
    ),
    MockPost(
      id: 'post2',
      category: 'walk_proxy',
      title: '주말 대리산책 부탁드려요 (사례 있음)',
      content: '이번 주말 출장이라 바둑이 산책을 부탁드릴 분을 찾아요. 1회 30분, 사례 드립니다.',
      authorNickname: '승주',
      authorUserType: 'pet_owner',
      createdAt: _now.subtract(const Duration(hours: 5)),
      heartCount: 8,
      commentCount: 3,
      scheduledAt: _now.add(const Duration(days: 2, hours: 10)),
      location: '반송동',
    ),
    MockPost(
      id: 'post3',
      category: 'care',
      title: '3박 4일 돌봄 가능하신 분 찾습니다',
      content: '휴가 기간 동안 콩이를 돌봐주실 분을 구해요. 집 방문 돌봄 선호합니다.',
      authorNickname: '민지',
      authorUserType: 'pet_owner',
      createdAt: _now.subtract(const Duration(hours: 8)),
      heartCount: 5,
      commentCount: 2,
      scheduledAt: _now.add(const Duration(days: 7)),
      location: '동탄1동',
    ),
    MockPost(
      id: 'post4',
      category: 'give_away',
      title: '사정상 분양 보냅니다 (책임비 있음)',
      content: '갑작스러운 사정으로 더 좋은 가족을 찾아드리려 합니다. 예방접종 완료, 중성화 완료된 아이예요.',
      authorNickname: '현우',
      authorUserType: 'pet_owner',
      createdAt: _now.subtract(const Duration(days: 1)),
      heartCount: 22,
      commentCount: 11,
      location: '병점동',
    ),
    MockPost(
      id: 'post5',
      category: 'adoption',
      title: '유기견 임시보호 후 입양 알아봐요',
      content: '구조한 아이의 평생 가족을 찾습니다. 입양 상담 가능하신 분 연락 주세요.',
      authorNickname: '소연',
      authorUserType: 'no_pet',
      createdAt: _now.subtract(const Duration(days: 1, hours: 4)),
      heartCount: 31,
      commentCount: 7,
      location: '동탄',
    ),
    MockPost(
      id: 'post6',
      category: 'free',
      title: '오늘 호수공원 강아지 모임 보신 분?',
      content: '오후에 산책하다 보니 강아지들이 엄청 많이 모여있던데 정기 모임인가요? 정보 아시는 분!',
      authorNickname: '지훈',
      authorUserType: 'no_pet',
      createdAt: _now.subtract(const Duration(days: 2)),
      heartCount: 3,
      commentCount: 9,
    ),
  ];

  static final List<MockChatRoom> chatRooms = [
    MockChatRoom(
      id: 'c1',
      otherNickname: '승주',
      lastMessage: '좋아요 그때 뵐게요!',
      lastAt: _now.subtract(const Duration(minutes: 12)),
      unreadCount: 1,
      postTitle: '동탄2동 저녁 산책 메이트 구해요',
    ),
    MockChatRoom(
      id: 'c2',
      otherNickname: '민지',
      lastMessage: '네 돌봄 일정 확인해보고 연락드릴게요',
      lastAt: _now.subtract(const Duration(hours: 3)),
      unreadCount: 0,
      postTitle: '3박 4일 돌봄 가능하신 분 찾습니다',
    ),
    MockChatRoom(
      id: 'c3',
      otherNickname: '현우',
      lastMessage: '사진 더 보내드릴게요~',
      lastAt: _now.subtract(const Duration(days: 1)),
      unreadCount: 0,
      postTitle: '사정상 분양 보냅니다',
    ),
  ];
}

/// 상대 시간 표시 헬퍼 ("방금 전", "3시간 전" 등).
/// 기준 시각은 목 데이터 일관성을 위해 [MockData] 기준 시각을 사용한다.
String timeAgo(DateTime time, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(time);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${time.month}월 ${time.day}일';
}

/// 카테고리 라벨 헬퍼.
String categoryLabel(String category) => switch (category) {
      'walk_together' => '동반산책',
      'walk_proxy' => '대리산책',
      'care' => '돌봄',
      'give_away' => '분양',
      'adoption' => '입양',
      'free' => '자유',
      _ => category,
    };
