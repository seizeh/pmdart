/// 게시글 **반응** — 하트·조회수·지원.
///
/// 조회(query)와 나눈 이유: 이쪽은 전부 **로그인 필수 + 낙관적 갱신**이고, 조회는
/// 비로그인도 도는 읽기 전용이다. 실패했을 때 사용자에게 보여 줄 것도 다르다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../error_reporter.dart';
import '../session.dart';

class PostEngagementRepository {
  PostEngagementRepository._();
  static final PostEngagementRepository instance = PostEngagementRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  String? get _uid => SessionManager.instance.user?.id;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError('로그인이 필요합니다');
    }
    return uid;
  }

  /// 하트 토글. 반환값은 토글 후 hearted 상태.
  ///
  /// [currentlyHearted] 는 UI 스냅샷이라 연타·다른 기기 조작으로 서버와 어긋날
  /// 수 있다 — 어긋나도 목표 상태로 수렴하게 관용 처리한다(#239): 이미 있는데
  /// INSERT(23505) 는 하트 성공으로, 없는 행 DELETE 는 원래 0행 성공이다.
  Future<bool> toggleHeart(String postId, bool currentlyHearted) async {
    final uid = _requireUid();
    if (currentlyHearted) {
      await _c
          .from('post_hearts')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', uid);
      return false;
    } else {
      try {
        await _c.from('post_hearts').insert({
          'post_id': postId,
          'user_id': uid,
        });
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow; // 중복 = 이미 하트 상태(목표와 동일)
      }
      return true;
    }
  }

  /// 게시글 조회 기록 — post_views INSERT 시 트리거가 view_count +1.
  /// (post_id, user_id, view_bucket) 부분 유니크로 같은 시간대 재조회는 중복 집계되지 않는다.
  /// 조회 리타이어는 1시간(시간 단위 버킷). 실제로 1 증가했으면 true(낙관적 표시용),
  /// 중복/비로그인/실패면 false.
  Future<bool> recordView(String postId) async {
    final uid = _uid;
    if (uid == null) return false; // 비로그인은 RLS상 기록 불가
    final now = DateTime.now().toUtc();
    final bucket = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).toIso8601String();
    try {
      await _c.from('post_views').insert({
        'post_id': postId,
        'user_id': uid,
        'view_bucket': bucket,
      });
      return true;
    } on PostgrestException catch (e) {
      // 23505 = 같은 버킷 내 중복 조회 → 정상(집계 안 됨)
      if (e.code == '23505') return false;
      return false;
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'community.recordView',
        why: '조회수 집계 실패 — 화면 표시와 무관하다',
      );
      return false;
    }
  }

  /// 게시글 지원.
  Future<void> apply(String postId, {String? message}) async {
    final uid = _requireUid();
    await _c.from('applications').insert({
      'post_id': postId,
      'applicant_id': uid,
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }

  /// 지원자 목록을 관리(조회·수락)할 수 있는지 — 작성자 또는 게시글 펫의 공동보호자.
  /// 비로그인/실패 시 false.
  Future<bool> canManageApplicants(String postId) async {
    if (_uid == null) return false;
    try {
      final res = await _c.rpc(
        'can_manage_post_applicants',
        params: {'p_post': postId},
      );
      return res == true;
    } catch (e, st) {
      // false 는 '권한 없음' 으로 읽혀 작성자에게 지원자 관리 버튼이 사라진다.
      ErrorReporter.report(
        e,
        where: 'community.canManageApplicants',
        stackTrace: st,
      );
      return false;
    }
  }
}
