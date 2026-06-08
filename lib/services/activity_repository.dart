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

  /// 내 약속 (글주인/지원자 모두).
  Future<List<Map<String, dynamic>>> fetchMyAppointments() async {
    final uid = _uid;
    final rows = await _c
        .from('appointments')
        .select('id, status, scheduled_at, created_at, posts(id, title, category)')
        .or('applicant_id.eq.$uid,post_owner_id.eq.$uid')
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 받은 평가.
  Future<List<Map<String, dynamic>>> fetchMyReviews() async {
    final rows = await _c
        .from('reviews')
        .select('id, categories, created_at')
        .eq('reviewee_id', _uid)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ── 알림 설정 ──────────────────────────────────────────────
  static const notificationKeys = <String, String>{
    'chat_message': '채팅 메시지',
    'post_application': '게시글 지원',
    'post_comment': '댓글',
    'pawing_new_post': 'Pawing 새 글',
    'application_accepted': '지원 수락',
    'review_received': '평가 수신',
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
    await _c.from('notification_preferences').upsert(
      {'user_id': _uid, key: value},
      onConflict: 'user_id',
    );
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
      for (final p in profs as List) p['id'] as String: p['nickname']
    };
    return [
      for (final r in list)
        {
          'blocked_id': r['blocked_id'],
          'created_at': r['created_at'],
          'nickname': nameById[r['blocked_id']] ?? '알 수 없음',
        }
    ];
  }

  Future<void> unblock(String blockedId) async {
    await _c
        .from('user_blocks')
        .delete()
        .eq('blocker_id', _uid)
        .eq('blocked_id', blockedId);
    AppEvents.instance.notifySocial();
  }
}
