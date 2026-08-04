/// 게시글 **작성·수정·삭제**와 공유 링크.
///
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/community.dart';
import '../error_reporter.dart';
import '../session.dart';
import '../storage_service.dart' show UploadedImage;

class PostWriteRepository {
  PostWriteRepository._();
  static final PostWriteRepository instance = PostWriteRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  String? get _uid => SessionManager.instance.user?.id;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError('로그인이 필요합니다');
    }
    return uid;
  }

  /// 게시글 작성. 반환값은 새 게시글 id.
  ///
  /// create_post_verified RPC 로 일원화(0018): 토큰 전달·INSERT·post_pets 연결·토큰
  /// 소진이 한 트랜잭션에서 일어난다. 사진 필수 카테고리는 [photoToken] 필수
  /// (서버 트리거가 검증), free/adoption 은 토큰 없이 호출.
  Future<String> createPost({
    required String category,
    required String title,
    required String content,
    DateTime? scheduledAt,
    List<String> petIds = const [],
    String? imageUrl,
    String? imageMime,
    int? imageSize,
    String? imageThumbUrl,
    String? photoToken,
  }) async {
    _requireUid();
    final postId = await _c.rpc(
      'create_post_verified',
      params: {
        'p_category': category,
        'p_title': title,
        'p_content': content,
        'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'p_pet_ids': petIds.isEmpty ? null : petIds,
        'p_image_url': imageUrl,
        'p_image_mime': imageMime,
        'p_image_size': imageSize,
        // 영상 첨부(free/news) 시 포스터 jpeg — 사진 글은 null.
        'p_image_thumb_url': imageThumbUrl,
        'p_photo_token': photoToken,
      },
    );
    return postId as String;
  }

  /// 이 게시글이 **수정 잠김**인가 — 약속이 한 건이라도 완료됐으면 true.
  ///
  /// 성사된 거래의 조건(제목·내용·일정)을 사후에 갈아끼우면 그걸 근거로 남은
  /// 후기·신뢰도가 흔들린다. 서버(`update_my_post`)가 정본으로 막고, 이 조회는
  /// 잠긴 이유를 **미리** 알려주기 위한 것이다(저장 눌러서 실패하지 않게).
  /// 실패 시 false — 안내를 못 띄울 뿐이고 저장은 서버가 막는다.
  Future<bool> postEditLocked(String postId) async {
    try {
      final r = await _c.rpc('post_edit_locked', params: {'p_post': postId});
      return r == true;
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'community.postEditLocked',
        why: '잠금 안내를 못 띄울 뿐 — 실제 차단은 update_my_post 가 한다',
      );
      return false;
    }
  }

  /// 내 게시글 제목·내용·약속일정·(자유/입양 한정)사진 수정 — update_my_post RPC.
  /// 일정이 실제로 바뀌면 진행 중 지원자에게 알림/푸시가 서버에서 발송된다.
  /// 카메라 인증 게시글의 검증 사진·카테고리·펫은 편집 대상이 아니다(서버가 무시).
  /// [scheduledAt] 은 일정 게시글이면 현재/변경 값, 아니면 null.
  /// [editImage] 가 true 면 자유/입양/소식 게시글의 미디어를 [image] 값으로
  /// 교체(null=제거). 영상으로 교체 시 [imageThumbUrl] 에 포스터를 전달한다.
  Future<void> updatePost(
    String postId, {
    required String title,
    required String content,
    DateTime? scheduledAt,
    bool editImage = false,
    UploadedImage? image,
    String? imageThumbUrl,
  }) async {
    _requireUid();
    await _c.rpc(
      'update_my_post',
      params: {
        'p_post': postId,
        'p_title': title,
        'p_content': content,
        'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'p_edit_image': editImage,
        'p_image_url': image?.url,
        'p_image_mime': image?.mime,
        'p_image_size': image?.size,
        'p_image_thumb_url': imageThumbUrl,
      },
    );
  }

  /// 게시글 공유 링크 발급 — 공유 뷰어(go.pawmate.kr) 토큰 반환.
  /// 서버가 게시글당 유효 링크를 재사용한다(30일, visible 게시글만).
  Future<String> createPostShareLink(String postId) async {
    _requireUid();
    final rows =
        await _c.rpc('create_post_share_link', params: {'p_post': postId})
            as List;
    return (rows.first as Map<String, dynamic>)['token'] as String;
  }

  /// 내 게시글 삭제(소프트) — delete_my_post RPC.
  /// 직접 UPDATE 는 결과 행이 posts_select 비가시라 RLS(42501)에 막히므로,
  /// 본인 확인 후 RLS 를 우회하는 SECURITY DEFINER RPC 로 처리한다.
  Future<void> deletePost(String postId) async {
    _requireUid();
    await _c.rpc('delete_my_post', params: {'p_post': postId});
  }

  /// 여러 게시글 일괄 삭제(소프트). 중간 실패가 나머지를 막지 않도록 끝까지
  /// 진행하고, 하나라도 실패하면 개수를 담아 던진다(#239 — 부분 실패 가시화).
  Future<void> deletePosts(Iterable<String> postIds) async {
    _requireUid();
    var failed = 0;
    for (final id in postIds) {
      try {
        await deletePost(id);
      } catch (e, st) {
        failed++;
        ErrorReporter.userFacing(
          e,
          where: 'community.deletePosts',
          stackTrace: st,
        );
      }
    }
    if (failed > 0) throw StateError('게시글 $failed개를 삭제하지 못했어요');
  }

  /// 내 반려동물 목록 (작성 시 연결용).
  Future<List<MyPet>> fetchMyPets() async {
    final uid = _requireUid();
    final rows = await _c
        .from('pet_guardians')
        .select(
          'role, pets(id, name, species, pet_status, identity_verified, '
          'pet_match_count, trust_score, verify_post_count)',
        )
        .eq('user_id', uid);
    final result = <MyPet>[];
    for (final r in rows as List) {
      final pet = r['pets'] as Map<String, dynamic>?;
      if (pet == null) continue;
      if (pet['pet_status'] != 'active') continue;
      result.add(
        MyPet(
          id: pet['id'] as String,
          name: (pet['name'] ?? '') as String,
          species: (pet['species'] ?? '') as String,
          role: (r['role'] ?? 'co_guardian') as String,
          isIdentityVerified: pet['identity_verified'] == true,
          matchCount: (pet['pet_match_count'] ?? 0) as int,
          trustScore: (pet['trust_score'] ?? 0) as int,
          verifyPostCount: (pet['verify_post_count'] ?? 0) as int,
        ),
      );
    }
    return result;
  }
}
