import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import '../data/mock_data.dart' show MockPet;
import '../models/profile.dart';
import 'app_events.dart';
import 'session.dart';

/// 내정보(프로필 헤더 / 활동·관심 통계 / 내 반려동물) 데이터 접근.
class ProfileRepository {
  ProfileRepository._();
  static final ProfileRepository instance = ProfileRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  Future<ProfileData> fetchProfile() async {
    final user = SessionManager.instance.user;
    if (user == null) throw StateError('로그인이 필요합니다');
    final uid = user.id;

    // 프로필 헤더(공개 프로필 뷰). 아이디(username)는 공개 뷰에 없으므로 세션에서 가져온다.
    final profile = await _c
        .from('public_profiles')
        .select('nickname, user_type')
        .eq('id', uid)
        .maybeSingle();

    // 통계 — 병렬 카운트
    final counts = await Future.wait([
      _count('reviews', 'reviewee_id', uid),
      _count('pawings', 'follower_id', uid),
      _count('pawings', 'following_id', uid),
      _count('posts', 'user_id', uid),
      _count('post_hearts', 'user_id', uid),
      _count('applications', 'applicant_id', uid),
      _appointmentCount(uid),
    ]);

    final pets = await _fetchMyPets(uid);

    return ProfileData(
      nickname: (profile?['nickname'] ?? user.nickname) as String,
      username: user.username,
      userType: (profile?['user_type'] ?? user.userType) as String,
      reviewCount: counts[0],
      pawingCount: counts[1],
      pawmateCount: counts[2],
      postCount: counts[3],
      heartCount: counts[4],
      applicationCount: counts[5],
      appointmentCount: counts[6],
      pets: pets,
    );
  }

  /// 타 사용자 공개 프로필 조회 (사용자 검색 → 프로필).
  /// 공개 뷰/공개 정책으로 읽을 수 있는 범위만 채운다.
  Future<PublicProfileData> fetchPublicProfile(String userId) async {
    final profile = await _c
        .from('public_profiles')
        .select('nickname, user_type, profile_image_url, address, is_location_verified')
        .eq('id', userId)
        .maybeSingle();
    if (profile == null) throw StateError('프로필을 찾을 수 없어요');

    // 통계 — 일부가 막혀 있어도 전체가 실패하지 않도록 개별 보호.
    final counts = await Future.wait([
      _count('reviews', 'reviewee_id', userId).catchError((_) => 0),
      _count('pawings', 'follower_id', userId).catchError((_) => 0),
      _count('pawings', 'following_id', userId).catchError((_) => 0),
      _count('posts', 'user_id', userId).catchError((_) => 0),
    ]);

    final pets = await _fetchPublicPets(userId);

    return PublicProfileData(
      userId: userId,
      nickname: (profile['nickname'] ?? '알 수 없음') as String,
      userType: (profile['user_type'] ?? '') as String,
      profileImageUrl: profile['profile_image_url'] as String?,
      address: profile['address'] as String?,
      isLocationVerified: profile['is_location_verified'] == true,
      reviewCount: counts[0],
      pawingCount: counts[1],
      pawmateCount: counts[2],
      postCount: counts[3],
      pets: pets,
    );
  }

  /// 타 사용자의 반려동물 — pet_guardians 는 타인 조회가 막혀 있어
  /// pets.primary_guardian_id 로 직접 조회한다(대표 보호자 기준).
  Future<List<MockPet>> _fetchPublicPets(String userId) async {
    try {
      final rows = await _c
          .from('pets')
          .select('id, name, species, gender, birth_date, bio, is_neutered, image_url')
          .eq('primary_guardian_id', userId)
          .eq('pet_status', 'active');
      return [
        for (final p in (rows as List).cast<Map<String, dynamic>>())
          MockPet(
            id: p['id'] as String,
            name: (p['name'] ?? '') as String,
            species: (p['species'] ?? '') as String,
            gender: p['gender'] as String?,
            birthDate: p['birth_date'] == null
                ? null
                : DateTime.parse(p['birth_date'] as String),
            bio: p['bio'] as String?,
            role: 'owner',
            guardianCount: 1,
            ownerName: '',
            isNeutered: p['is_neutered'] == true,
            imageUrl: p['image_url'] as String?,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 단일 컬럼 동등 필터 카운트.
  Future<int> _count(String table, String col, String val) async {
    final res =
        await _c.from(table).select('id').eq(col, val).count(CountOption.exact);
    return res.count;
  }

  /// 진행 중(scheduled) 약속 수 — 내가 글주인 또는 지원자.
  Future<int> _appointmentCount(String uid) async {
    final res = await _c
        .from('appointments')
        .select('id')
        .or('applicant_id.eq.$uid,post_owner_id.eq.$uid')
        .eq('status', 'scheduled')
        .count(CountOption.exact);
    return res.count;
  }

  /// 내 반려동물 + 보호자 수/소유자명 채워 MockPet 으로 반환
  /// (PetCard / PetDetailScreen 이 MockPet 을 사용하므로 그대로 매핑).
  Future<List<MockPet>> _fetchMyPets(String uid) async {
    final rows = await _c
        .from('pet_guardians')
        .select(
            'role, pets(id, name, species, gender, birth_date, bio, is_neutered, image_url, pet_status, primary_guardian_id)')
        .eq('user_id', uid);

    final pets = <Map<String, dynamic>>[];
    final myRole = <String, String>{};
    for (final r in rows as List) {
      final p = r['pets'] as Map<String, dynamic>?;
      if (p == null || p['pet_status'] != 'active') continue;
      pets.add(p);
      myRole[p['id'] as String] = (r['role'] ?? 'co_guardian') as String;
    }
    if (pets.isEmpty) return const [];

    final petIds = pets.map((p) => p['id'] as String).toList();
    final ownerIds = pets
        .map((p) => p['primary_guardian_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    // 펫별 보호자 수
    final guardianRows =
        await _c.from('pet_guardians').select('pet_id').inFilter('pet_id', petIds);
    final guardianCount = <String, int>{};
    for (final g in guardianRows as List) {
      final pid = g['pet_id'] as String;
      guardianCount[pid] = (guardianCount[pid] ?? 0) + 1;
    }

    // 소유자 닉네임
    final ownerName = <String, String>{};
    if (ownerIds.isNotEmpty) {
      final owners = await _c
          .from('public_profiles')
          .select('id, nickname')
          .inFilter('id', ownerIds);
      for (final o in owners as List) {
        ownerName[o['id'] as String] = (o['nickname'] ?? '') as String;
      }
    }

    return pets.map((p) {
      final id = p['id'] as String;
      final ownerId = p['primary_guardian_id'] as String?;
      return MockPet(
        id: id,
        name: (p['name'] ?? '') as String,
        species: (p['species'] ?? '') as String,
        gender: p['gender'] as String?,
        birthDate:
            p['birth_date'] == null ? null : DateTime.parse(p['birth_date'] as String),
        bio: p['bio'] as String?,
        role: myRole[id] ?? 'co_guardian',
        guardianCount: guardianCount[id] ?? 1,
        ownerName: ownerId == null ? '' : (ownerName[ownerId] ?? ''),
        isNeutered: p['is_neutered'] == true,
        imageUrl: p['image_url'] as String?,
      );
    }).toList();
  }

  /// 프로필 수정 (닉네임 등). RLS: users_update (id=app.uid()).
  Future<void> updateProfile({String? nickname, String? profileImageUrl}) async {
    final user = SessionManager.instance.user;
    if (user == null) throw StateError('로그인이 필요합니다');
    final data = <String, dynamic>{};
    if (nickname != null) data['nickname'] = nickname;
    if (profileImageUrl != null) data['profile_image_url'] = profileImageUrl;
    if (data.isEmpty) return;
    await _c.from('users').update(data).eq('id', user.id);
    // 세션의 닉네임도 갱신
    if (nickname != null) {
      await SessionManager.instance.setSession(
        SessionManager.instance.token!,
        AuthUser(
          id: user.id,
          username: user.username,
          nickname: nickname,
          userType: user.userType,
        ),
      );
    }
    AppEvents.instance.notifyProfile();
  }
}
