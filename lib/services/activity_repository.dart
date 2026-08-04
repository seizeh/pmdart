import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_events.dart';
import 'session.dart';

/// 내 활동/관심/설정 데이터 (지원·약속·평가·알림설정·차단).
class ActivityRepository {
  ActivityRepository._();
  static final ActivityRepository instance = ActivityRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String get _uid {
    final id = SessionManager.instance.user?.id;
    if (id == null) throw StateError('로그인이 필요합니다');
    return id;
  }

  /// 내 지원 내역 (+ 게시글 제목/카테고리).
  Future<List<Map<String, dynamic>>> fetchMyApplications() async {
    final rows = await _c
        .from('applications')
        .select('id, status, message, created_at, posts(id, title, category)')
        .eq('applicant_id', _uid)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 내 약속 (글주인/지원자 모두). 평가 상대 판별용으로 양측 id 포함.
  Future<List<Map<String, dynamic>>> fetchMyAppointments() async {
    final uid = _uid;
    final rows = await _c
        .from('appointments')
        .select(
          'id, status, scheduled_at, created_at, post_owner_id, applicant_id, posts(id, title, category)',
        )
        .or('applicant_id.eq.$uid,post_owner_id.eq.$uid')
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// id → 닉네임 맵 (public_profiles).
  Future<Map<String, String>> fetchNicknames(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _c
        .from('public_profiles')
        .select('id, nickname')
        .inFilter('id', ids);
    return {
      for (final p in rows as List)
        p['id'] as String: (p['nickname'] as String?) ?? '알 수 없음',
    };
  }

  /// 내가 작성한 평가의 약속 id 집합 (평가 완료 여부 표시용).
  Future<Set<String>> fetchMyReviewedAppointmentIds() async {
    final rows = await _c
        .from('reviews')
        .select('appointment_id')
        .eq('reviewer_id', _uid);
    return {for (final r in rows as List) r['appointment_id'] as String};
  }

  /// 약속 완료 처리 (당사자만). 완료되면 평가 작성 가능.
  Future<void> completeAppointment(String appointmentId) async {
    await _c
        .from('appointments')
        .update({'status': 'completed'})
        .eq('id', appointmentId);
    AppEvents.instance.notifyProfile();
  }

  /// 평가 작성. categories 는 1~4개, 상반쌍 동시 선택 금지(DB CHECK).
  Future<void> submitReview({
    required String appointmentId,
    required String revieweeId,
    required List<String> categories,
  }) async {
    await _c.from('reviews').insert({
      'appointment_id': appointmentId,
      'reviewer_id': _uid,
      'reviewee_id': revieweeId,
      'categories': categories,
    });
    AppEvents.instance.notifyProfile();
  }

  /// 받은 평가 카테고리별 집계 (review_category_counts). category → count.
  Future<Map<String, int>> fetchReviewCounts([String? userId]) async {
    final rows = await _c
        .from('review_category_counts')
        .select('category, count')
        .eq('user_id', userId ?? _uid);
    return {
      for (final r in rows as List)
        r['category'] as String: (r['count'] as num).toInt(),
    };
  }

  // ── 지원자 관리 (글 작성자) ─────────────────────────────────
  /// 내 게시글의 지원자 목록 (+ 닉네임). RLS: 글 작성자만 조회 가능.
  Future<List<Map<String, dynamic>>> fetchApplicants(String postId) async {
    final rows = await _c
        .from('applications')
        .select('id, applicant_id, message, status, created_at')
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return list;
    final ids = [for (final r in list) r['applicant_id'] as String];
    final profs = await _c
        .from('public_profiles')
        .select('id, nickname')
        .inFilter('id', ids);
    final nameById = {
      for (final p in profs as List)
        p['id'] as String: (p['nickname'] as String?) ?? '알 수 없음',
    };
    return [
      for (final r in list)
        {...r, 'nickname': nameById[r['applicant_id']] ?? '알 수 없음'},
    ];
  }

  /// 지원자 수락 → DB 트리거가 약속 생성 + 나머지 지원자 자동 거절.
  Future<void> acceptApplication(String applicationId) async {
    await _c
        .from('applications')
        .update({'status': 'accepted'})
        .eq('id', applicationId);
    AppEvents.instance.notifyProfile();
  }

  // ── 알림 설정 ──────────────────────────────────────────────
  static const notificationKeys = <String, String>{
    'chat_message': '채팅 메시지',
    'post_application': '게시글 지원',
    'post_comment': '댓글',
    'pawing_new_post': 'Pawing 새 글',
    'application_accepted': '지원 수락',
    'review_received': '후기 수신',
    'system_notice': '시스템 공지',
  };

  /// 알림 설정 행 조회 (없으면 빈 맵 → 기본 true 취급).
  Future<Map<String, dynamic>> fetchNotificationPrefs() async {
    final row = await _c
        .from('notification_preferences')
        .select()
        .eq('user_id', _uid)
        .maybeSingle();
    return row ?? <String, dynamic>{};
  }

  /// 알림 설정 항목 변경 (upsert).
  Future<void> setNotificationPref(String key, bool value) async {
    await _c.from('notification_preferences').upsert({
      'user_id': _uid,
      key: value,
    }, onConflict: 'user_id');
  }

  // ── 차단 ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchBlockedUsers() async {
    final rows = await _c
        .from('user_blocks')
        .select('blocked_id, created_at')
        .eq('blocker_id', _uid)
        .order('created_at', ascending: false);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return list;
    final ids = [for (final r in list) r['blocked_id'] as String];
    final profs = await _c
        .from('public_profiles')
        .select('id, nickname')
        .inFilter('id', ids);
    final nameById = {
      for (final p in profs as List) p['id'] as String: p['nickname'],
    };
    return [
      for (final r in list)
        {
          'blocked_id': r['blocked_id'],
          'created_at': r['created_at'],
          'nickname': nameById[r['blocked_id']] ?? '알 수 없음',
        },
    ];
  }

  /// 차단 해제. 이벤트는 차단과 대칭으로 쏜다(report_repository.block 참고) —
  /// social 만 쏘면 차단 목록은 갱신되는데 **커뮤니티 피드는 그 사람 글이 다시
  /// 보여야 하는데도 그대로**다. 커뮤니티 탭은 feed 만 구독한다.
  Future<void> unblock(String blockedId) async {
    await _c
        .from('user_blocks')
        .delete()
        .eq('blocker_id', _uid)
        .eq('blocked_id', blockedId);
    AppEvents.instance.notifySocial();
    AppEvents.instance.notifyFeed();
    AppEvents.instance.notifyChat();
  }
}
