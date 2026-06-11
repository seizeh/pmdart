import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/social.dart';
import '../models/pet_search.dart';
import 'app_events.dart';
import 'session.dart';

/// Pawing(팔로우) 시스템 + 사용자 검색.
class SocialRepository {
  SocialRepository._();
  static final SocialRepository instance = SocialRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String get _uid {
    final id = SessionManager.instance.user?.id;
    if (id == null) throw StateError('로그인이 필요합니다');
    return id;
  }

  /// 팔로우(Pawing). 이미 팔로우 중이면 무시.
  Future<void> follow(String userId) async {
    await _c.from('pawings').upsert(
      {'follower_id': _uid, 'following_id': userId},
      onConflict: 'follower_id,following_id',
      ignoreDuplicates: true,
    );
    AppEvents.instance.notifySocial();
  }

  /// 언팔로우.
  Future<void> unfollow(String userId) async {
    await _c
        .from('pawings')
        .delete()
        .eq('follower_id', _uid)
        .eq('following_id', userId);
    AppEvents.instance.notifySocial();
  }

  /// 내가 [userId] 를 팔로우 중인지.
  Future<bool> isFollowing(String userId) async {
    final rows = await _c
        .from('pawings')
        .select('following_id')
        .eq('follower_id', _uid)
        .eq('following_id', userId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// 내가 팔로우하는 사람들 (Pawing).
  Future<List<Connection>> fetchPawing() async {
    final rows = await _c
        .from('v_pawing')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Connection.fromJson(r as Map<String, dynamic>)
            .copyWith(following: true))
        .toList();
  }

  /// 나를 팔로우하는 사람들 (Pawmate).
  Future<List<Connection>> fetchPawmate() async {
    final rows = await _c
        .from('v_pawmate')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Connection.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 사용자 검색 (닉네임). 나 자신은 제외, 팔로우 여부 포함.
  /// 아이디(username)는 비공개 값이라 검색 대상에서 제외한다.
  Future<List<Connection>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uid = _uid;
    final rows = await _c
        .from('public_profiles')
        .select('id, nickname, user_type')
        .ilike('nickname', '%$q%')
        .neq('id', uid)
        .limit(30);

    final list = (rows as List)
        .map((r) => Connection.fromJson(r as Map<String, dynamic>))
        .toList();
    if (list.isEmpty) return list;

    // 내가 팔로우 중인 대상 표시
    final ids = list.map((c) => c.userId).toList();
    final following = await _c
        .from('pawings')
        .select('following_id')
        .eq('follower_id', uid)
        .inFilter('following_id', ids);
    final followingSet = {
      for (final f in following as List) f['following_id'] as String
    };
    return list
        .map((c) => c.copyWith(following: followingSet.contains(c.userId)))
        .toList();
  }

  /// 반려동물 이름으로 검색. 삭제된 펫 제외. 결과 탭의 '반려동물' 섹션용.
  /// pets_select RLS: 삭제되지 않은 펫은 누구나 조회 가능.
  Future<List<PetHit>> searchPets(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final rows = await _c
        .from('pets')
        .select('id, name, species, image_url, primary_guardian_id')
        .ilike('name', '%$q%')
        .neq('pet_status', 'deleted')
        .limit(20);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const [];

    // 보호자(소유자) 닉네임 채우기
    final ownerIds = <String>{
      for (final r in list)
        if (r['primary_guardian_id'] != null) r['primary_guardian_id'] as String
    }.toList();
    final nameById = <String, String>{};
    if (ownerIds.isNotEmpty) {
      final profs = await _c
          .from('public_profiles')
          .select('id, nickname')
          .inFilter('id', ownerIds);
      for (final p in profs as List) {
        nameById[p['id'] as String] = (p['nickname'] ?? '') as String;
      }
    }
    return [
      for (final r in list)
        PetHit(
          id: r['id'] as String,
          name: (r['name'] ?? '') as String,
          species: (r['species'] ?? '') as String,
          imageUrl: r['image_url'] as String?,
          ownerNickname: nameById[r['primary_guardian_id']] ?? '',
        )
    ];
  }
}
