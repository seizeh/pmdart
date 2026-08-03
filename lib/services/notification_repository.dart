import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification.dart';
import 'app_events.dart';
import 'session.dart';

/// 알림(notifications) — 조회/안읽음 수/읽음 처리.
/// 알림 생성은 서버(트리거/관리자)만 가능. 클라이언트는 읽기 + 읽음 처리만.
class NotificationRepository {
  NotificationRepository._();
  static final NotificationRepository instance = NotificationRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String? get _uid => SessionManager.instance.user?.id;

  /// 내 알림 목록 (사용자에게 보이는 것만, 최신순).
  Future<List<AppNotification>> fetch() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('notifications')
        .select(
          'id, notification_type, title, body, is_read, created_at, resource_type, resource_id, aggregated_count',
        )
        .eq('user_id', uid)
        .eq('is_silent', false)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .map((r) => AppNotification.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 안읽은 알림 수.
  Future<int> unreadCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    final res = await _c
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_silent', false)
        .eq('is_read', false)
        .count(CountOption.exact);
    return res.count;
  }

  /// 단건 읽음 처리 (트리거가 read_at·안읽음 카운트 자동 갱신).
  Future<void> markRead(String id) async {
    await _c.from('notifications').update({'is_read': true}).eq('id', id);
    AppEvents.instance.notifyNotification();
  }

  /// 단건 삭제 — 확인한 알림은 목록에서 제거.
  ///
  /// 삭제 전에 반드시 읽음 처리(UPDATE)를 선행한다 — 서버 unread 카운터
  /// 트리거에 DELETE 분기가 없어, 안읽음 행을 바로 지우면 카운터(푸시 배지)가
  /// 영구히 감소하지 않는다(#232). 읽음 후 삭제가 실패해도 카운터는 정확하고
  /// 알림만 남는다(다음 삭제 시도로 수렴).
  Future<void> delete(String id) async {
    await _c
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id)
        .eq('is_read', false);
    await _c.from('notifications').delete().eq('id', id);
    AppEvents.instance.notifyNotification();
  }

  /// 내 알림 전체 삭제 — '모두 읽음'(확인) 시.
  /// 단건 삭제와 동일하게 읽음 처리 선행(#232 — 트리거 DELETE 분기 부재).
  Future<void> deleteAll() async {
    final uid = _uid;
    if (uid == null) return;
    await _c
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
    await _c.from('notifications').delete().eq('user_id', uid);
    AppEvents.instance.notifyNotification();
  }

  /// 모두 읽음 처리.
  Future<void> markAllRead() async {
    final uid = _uid;
    if (uid == null) return;
    await _c
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
    AppEvents.instance.notifyNotification();
  }
}
