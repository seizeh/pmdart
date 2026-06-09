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
            'id, notification_type, title, body, is_read, created_at, resource_type, resource_id, aggregated_count')
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
