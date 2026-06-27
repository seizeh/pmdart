import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mock_data.dart' show MockPet;
import '../models/pet_search.dart';
import 'app_events.dart';
import 'session.dart';

/// 펫 보호자 1명.
class Guardian {
  final String userId;
  final String nickname;
  final String role; // owner / co_guardian
  final bool isMe;

  const Guardian({
    required this.userId,
    required this.nickname,
    required this.role,
    required this.isMe,
  });
}

/// 받은 공동보호자 초대 1건.
class GuardianInvite {
  final String id;
  final String petId;
  final String petName;
  final String petSpecies;
  final String? petImageUrl;
  final String inviterNickname;
  final DateTime createdAt;

  const GuardianInvite({
    required this.id,
    required this.petId,
    required this.petName,
    required this.petSpecies,
    required this.petImageUrl,
    required this.inviterNickname,
    required this.createdAt,
  });
}

/// 반려동물 등록/수정/삭제/보호자 관리.
class PetRepository {
  PetRepository._();
  static final PetRepository instance = PetRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String get _uid {
    final id = SessionManager.instance.user?.id;
    if (id == null) throw StateError('로그인이 필요합니다');
    return id;
  }

  /// 펫 등록 — pets INSERT (owner pet_guardian 행은 트리거가 자동 생성).
  Future<String> createPet({
    required String name,
    required String species,
    String? speciesKind, // 'dog' | 'cat'
    String? gender,
    DateTime? birthDate,
    String? bio,
    bool isNeutered = false,
    String? imageUrl,
  }) async {
    final data = <String, dynamic>{
      'primary_guardian_id': _uid,
      'name': name,
      'species': species,
      'is_neutered': isNeutered,
    };
    if (speciesKind != null) data['species_kind'] = speciesKind;
    if (gender != null) data['gender'] = gender;
    if (birthDate != null) {
      data['birth_date'] =
          birthDate.toIso8601String().split('T').first; // date only
    }
    if (bio != null && bio.isNotEmpty) data['bio'] = bio;
    if (imageUrl != null) data['image_url'] = imageUrl;

    final row = await _c.from('pets').insert(data).select('id').single();
    AppEvents.instance.notifyProfile();
    return row['id'] as String;
  }

  /// 펫 수정 (owner). RLS: pets_update.
  Future<void> updatePet(
    String petId, {
    required String name,
    required String species,
    String? speciesKind, // 'dog' | 'cat'
    String? gender,
    DateTime? birthDate,
    String? bio,
    bool isNeutered = false,
    String? imageUrl,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'species': species,
      'is_neutered': isNeutered,
      'gender': gender,
      'birth_date': birthDate?.toIso8601String().split('T').first,
      'bio': (bio == null || bio.isEmpty) ? null : bio,
    };
    if (speciesKind != null) data['species_kind'] = speciesKind;
    if (imageUrl != null) data['image_url'] = imageUrl;
    await _c.from('pets').update(data).eq('id', petId);
    AppEvents.instance.notifyProfile();
  }

  /// 펫 삭제 (soft delete: pet_status='deleted'). owner 만.
  Future<void> deletePet(String petId) async {
    await _c.from('pets').update({'pet_status': 'deleted'}).eq('id', petId);
    AppEvents.instance.notifyProfile();
  }

  /// 펫 단건 조회 (헤더용 — 내 역할/보호자 수/소유자명 포함). 삭제된 펫은 null.
  Future<MockPet?> fetchPet(String petId) async {
    final uid = _uid;
    final p = await _c
        .from('pets')
        .select(
            'id, name, species, species_kind, gender, birth_date, bio, is_neutered, image_url, pet_status, primary_guardian_id, ai_ref_image_url, pet_match_count')
        .eq('id', petId)
        .maybeSingle();
    if (p == null || p['pet_status'] == 'deleted') return null;

    final mine = await _c
        .from('pet_guardians')
        .select('role')
        .eq('pet_id', petId)
        .eq('user_id', uid)
        .maybeSingle();
    final guardianRows =
        await _c.from('pet_guardians').select('user_id').eq('pet_id', petId);
    final ownerId = p['primary_guardian_id'] as String?;
    var ownerName = '';
    if (ownerId != null) {
      final o = await _c
          .from('public_profiles')
          .select('nickname')
          .eq('id', ownerId)
          .maybeSingle();
      ownerName = (o?['nickname'] ?? '') as String;
    }
    return MockPet(
      id: p['id'] as String,
      name: (p['name'] ?? '') as String,
      species: (p['species'] ?? '') as String,
      speciesKind: p['species_kind'] as String?,
      gender: p['gender'] as String?,
      birthDate: p['birth_date'] == null
          ? null
          : DateTime.parse(p['birth_date'] as String),
      bio: p['bio'] as String?,
      role: (mine?['role'] ?? 'co_guardian') as String,
      guardianCount: (guardianRows as List).length,
      ownerName: ownerName,
      isNeutered: p['is_neutered'] == true,
      imageUrl: p['image_url'] as String?,
      hasAiReference: p['ai_ref_image_url'] != null,
      matchCount: (p['pet_match_count'] ?? 0) as int,
    );
  }

  /// 공개 펫 프로필 (read-only) — 검색에서 진입. 보호자가 아닌 사용자도 조회 가능.
  /// 삭제된 펫은 null. 보호자/역할 정보는 노출하지 않는다.
  Future<PetProfile?> fetchPublicPet(String petId) async {
    final p = await _c
        .from('pets')
        .select(
            'id, name, species, gender, birth_date, bio, is_neutered, image_url, pet_status, primary_guardian_id, ai_ref_image_url, pet_match_count')
        .eq('id', petId)
        .maybeSingle();
    if (p == null || p['pet_status'] == 'deleted') return null;

    final ownerId = p['primary_guardian_id'] as String?;
    var ownerName = '';
    if (ownerId != null) {
      final o = await _c
          .from('public_profiles')
          .select('nickname')
          .eq('id', ownerId)
          .maybeSingle();
      ownerName = (o?['nickname'] ?? '') as String;
    }
    return PetProfile(
      id: p['id'] as String,
      name: (p['name'] ?? '') as String,
      species: (p['species'] ?? '') as String,
      gender: p['gender'] as String?,
      birthDate: p['birth_date'] == null
          ? null
          : DateTime.parse(p['birth_date'] as String),
      isNeutered: p['is_neutered'] == true,
      bio: p['bio'] as String?,
      imageUrl: p['image_url'] as String?,
      ownerId: ownerId ?? '',
      ownerNickname: ownerName,
      hasAiReference: p['ai_ref_image_url'] != null,
      matchCount: (p['pet_match_count'] ?? 0) as int,
    );
  }

  /// 펫 보호자 목록.
  Future<List<Guardian>> fetchGuardians(String petId) async {
    final uid = _uid;
    final rows = await _c
        .from('pet_guardians')
        .select('user_id, role, public_profiles(nickname)')
        .eq('pet_id', petId);
    return (rows as List).map((r) {
      final prof = r['public_profiles'] as Map<String, dynamic>?;
      final userId = r['user_id'] as String;
      return Guardian(
        userId: userId,
        nickname: (prof?['nickname'] ?? '알 수 없음') as String,
        role: (r['role'] ?? 'co_guardian') as String,
        isMe: userId == uid,
      );
    }).toList();
  }

  /// 공동보호자 초대 (전화번호). owner 만.
  Future<void> invite(String petId, String phone) async {
    await _c.from('pet_guardian_invites').insert({
      'pet_id': petId,
      'kind': 'invite',
      'inviter_id': _uid,
      'invitee_phone': phone,
    });
  }

  /// 나에게 온 대기 중 공동보호자 초대 수.
  Future<int> pendingInviteCount() async {
    final id = SessionManager.instance.user?.id;
    if (id == null) return 0;
    final res = await _c
        .from('pet_guardian_invites')
        .select('id')
        .eq('invitee_user_id', id)
        .eq('status', 'pending')
        .eq('kind', 'invite')
        .count(CountOption.exact);
    return res.count;
  }

  /// 나에게 온 대기 중 공동보호자 초대 목록 (+ 펫/초대자 정보).
  Future<List<GuardianInvite>> fetchPendingInvites() async {
    final uid = _uid;
    final rows = await _c
        .from('pet_guardian_invites')
        .select('id, created_at, pet_id, inviter_id')
        .eq('invitee_user_id', uid)
        .eq('status', 'pending')
        .eq('kind', 'invite')
        .order('created_at', ascending: false);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const [];

    final petIds = <String>{for (final r in list) r['pet_id'] as String}.toList();
    final inviterIds =
        <String>{for (final r in list) r['inviter_id'] as String}.toList();

    final pets = await _c
        .from('pets')
        .select('id, name, species, image_url')
        .inFilter('id', petIds);
    final petById = {
      for (final p in pets as List) p['id'] as String: p as Map<String, dynamic>
    };
    final profs = await _c
        .from('public_profiles')
        .select('id, nickname')
        .inFilter('id', inviterIds);
    final nameById = {
      for (final p in profs as List) p['id'] as String: (p['nickname'] ?? '') as String
    };

    return [
      for (final r in list)
        GuardianInvite(
          id: r['id'] as String,
          petId: r['pet_id'] as String,
          petName: (petById[r['pet_id']]?['name'] ?? '알 수 없음') as String,
          petSpecies: (petById[r['pet_id']]?['species'] ?? '') as String,
          petImageUrl: petById[r['pet_id']]?['image_url'] as String?,
          inviterNickname: nameById[r['inviter_id']] ?? '알 수 없음',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        )
    ];
  }

  /// 초대 수락 → 트리거가 공동보호자로 등록.
  /// 진행 중 약속의 지원자면 DB 트리거가 막아 PostgrestException 을 던진다(메시지 노출용).
  Future<void> acceptInvite(String inviteId) async {
    await _c
        .from('pet_guardian_invites')
        .update({'status': 'accepted'}).eq('id', inviteId);
    AppEvents.instance.notifyProfile();
  }

  /// 초대 거절.
  Future<void> declineInvite(String inviteId) async {
    await _c
        .from('pet_guardian_invites')
        .update({'status': 'declined'}).eq('id', inviteId);
    AppEvents.instance.notifyProfile();
  }

  /// 공동보호자 제거 (owner). 본인/owner 는 제거 불가(트리거/규칙).
  Future<void> removeGuardian(String petId, String userId) async {
    await _c
        .from('pet_guardians')
        .delete()
        .eq('pet_id', petId)
        .eq('user_id', userId);
    AppEvents.instance.notifyProfile();
  }
}
