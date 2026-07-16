import 'package:supabase_flutter/supabase_flutter.dart';
import 'session.dart';
import 'app_events.dart';

/// 앱 전역 Realtime — 로그인 세션의 커스텀 JWT 로 realtime 을 인증하고,
/// 내 알림(notifications) insert 를 구독해 화면 갱신 이벤트를 발화한다.
///  · 벨 배지/알림 목록: AppEvents.notification
///  · 채팅 목록(새 메시지 알림): AppEvents.chat  (열려있는 채팅방 내부는 chat_repository 구독이 담당)
/// realtime 연결은 앱 시작 시 비로그인(anon)으로 붙을 수 있어, 로그인/토큰갱신 때
/// setAuth 로 재인증해야 RLS(app.uid) 를 통과해 이벤트가 도착한다.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  SupabaseClient get _c => Supabase.instance.client;
  RealtimeChannel? _notif;

  /// 새 알림 도착 시 인앱 배너 표시용(알림 행 원본 전달) — main.dart 가 세팅.
  /// FCM 포그라운드 푸시 대신 이 경로를 쓴다: 기기 토큰(APNs/FCM) 유무와 무관하게
  /// 앱이 켜져 있으면 항상 동작한다(시뮬레이터 포함).
  void Function(Map<String, dynamic> row)? onNotificationBanner;

  /// 로그인 후/앱 시작(로그인 상태) 시 호출. realtime 재인증 + 알림 구독.
  void start() {
    final me = SessionManager.instance.user?.id;
    final token = SessionManager.instance.token;
    if (me == null || token == null) return;
    _c.realtime.setAuth(token); // 커스텀 JWT 로 realtime 인증(RLS 통과)
    if (_notif != null) return; // 이미 구독 중
    _notif = _c
        .channel('rt:notifications:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: me,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final type = row['notification_type'];
            AppEvents.instance.notifyNotification(); // 벨 배지/알림 목록 갱신
            if (type == 'chat_message') {
              AppEvents.instance.notifyChat(); // 채팅 목록 갱신
            }
            // 무음 알림(동기화용 등)은 배너 제외.
            if (row['is_silent'] != true) onNotificationBanner?.call(row);
          },
        )
        .subscribe();
  }

  /// 로그아웃/세션 무효화 시 — 구독 해제.
  void stop() {
    if (_notif != null) {
      _c.removeChannel(_notif!);
      _notif = null;
    }
  }
}
