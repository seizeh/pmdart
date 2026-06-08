import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mock_data.dart' show MockPet;
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
            'id, name, species, gender, birth_date, bio, is_neutered, image_url, pet_status, primary_guardian_id')
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
