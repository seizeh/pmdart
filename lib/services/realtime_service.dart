import 'dart:async';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_events.dart';
import 'error_reporter.dart';
import 'session.dart';

/// 구독이 끊겼을 때 다음 재시도까지 기다릴 시간.
///
/// 최상위 함수로 뺀 이유: 구독 상태 기계는 웹소켓이 필요해 단위 테스트가 어려운데,
/// 백오프 규칙은 순수 계산이라 테스트할 수 있다. 규칙을 바꾸면 테스트가 잡는다.
///
/// 1회차 2초 → 배로 늘리되 60초에서 멈춘다. 상한을 두는 이유는 네트워크가 오래
/// 끊긴 경우에도 복구가 1분 안에는 시도되게 하기 위해서다(무한히 벌어지면 사용자가
/// 앱을 껐다 켜야 하고, 그건 이 수정이 없애려는 상태 그 자체다).
Duration realtimeRetryDelay(int attempt) {
  if (attempt < 1) return const Duration(seconds: 2);
  final seconds = math.min(60, 2 << math.min(attempt - 1, 5));
  return Duration(seconds: seconds);
}

/// 앱 전역 Realtime — 로그인 세션의 커스텀 JWT 로 realtime 을 인증하고,
/// 내 알림(notifications) insert 를 구독해 화면 갱신 이벤트를 발화한다.
///  · 벨 배지/알림 목록: AppEvents.notification
///  · 채팅 목록(새 메시지 알림): AppEvents.chat  (열려있는 채팅방 내부는 chat_repository 구독이 담당)
/// realtime 연결은 앱 시작 시 비로그인(anon)으로 붙을 수 있어, 로그인/토큰갱신 때
/// setAuth 로 재인증해야 RLS(app.uid) 를 통과해 이벤트가 도착한다.
///
/// ── 구독 실패는 조용히 영구화된다 (2026-08-04 수정, 0031 §5.1)
/// 종전에는 `.subscribe()` 를 콜백 없이 불러 CHANNEL_ERROR·TIMED_OUT 을 몰랐다.
/// 첫 구독이 실패해도 `_notif` 에는 채널 객체가 들어가 non-null 이 되므로,
/// **이후 모든 start() 가 "이미 구독 중" 으로 조기 리턴하는 no-op** 이 됐다.
/// 앱을 껐다 켜기 전까지 벨 배지와 채팅 목록 실시간 갱신이 죽어 있는데,
/// FCM 푸시는 별개 경로라 계속 오므로 사용자는 "가끔 배지가 안 맞네" 정도로만
/// 느끼고 신고하지 않는다 — 그래서 오래 살아남을 수 있는 결함이었다.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  SupabaseClient get _c => Supabase.instance.client;
  RealtimeChannel? _notif;
  Timer? _retry;

  /// 연속 실패 횟수(백오프용). 구독 성공 시 0 으로 되돌린다.
  int _attempt = 0;

  /// 채널 세대. 끊긴 채널의 뒤늦은 콜백을 무시하는 데 쓴다 — removeChannel 이
  /// closed 콜백을 한 번 더 발화시키므로 이게 없으면 재시도가 이중으로 잡힌다.
  int _gen = 0;

  /// 구독을 원하는 상태인가. stop()(로그아웃·세션 무효화)이 false 로 만든다.
  /// **재구독 여부의 유일한 근거** — 우리가 끊은 것과 서버가 끊은 것을 구분한다.
  bool _wanted = false;

  /// 새 알림 도착 시 인앱 배너 표시용(알림 행 원본 전달) — main.dart 가 세팅.
  /// FCM 포그라운드 푸시 대신 이 경로를 쓴다: 기기 토큰(APNs/FCM) 유무와 무관하게
  /// 앱이 켜져 있으면 항상 동작한다(시뮬레이터 포함).
  void Function(Map<String, dynamic> row)? onNotificationBanner;

  /// 로그인 후/앱 시작(로그인 상태)/포그라운드 복귀 시 호출. realtime 재인증 + 구독.
  /// 여러 번 불러도 안전하다.
  /// 구독 시작 — **토큰을 먼저 확인한다.**
  ///
  /// 종전에는 저장된 access 를 그대로 setAuth 에 넘겼다. 콜드 스타트에서 그 토큰은
  /// 이미 만료돼 있는 경우가 많다(운영 로그: `InvalidJWTToken: Token has expired
  /// 42831 / 78585 / 201041 seconds ago`). REST 는 관문(accessToken 콜백)이 알아서
  /// 갱신해 주지만 **realtime 소켓 auth 는 setAuth 를 다시 불러야만 바뀐다** —
  /// 그래서 앱을 켜자마자 알림 구독이 조용히 죽어 있었다.
  ///
  /// 재시도 경로(_scheduleRetry)가 같은 일을 하고 있었는데, 그건 이미 끊긴 뒤의
  /// 복구라 **첫 연결은 덮지 못했다**(#236 이 웜 리줌만 커버한 이유).
  Future<void> start() async {
    final s = SessionManager.instance;
    final me = s.user?.id;
    if (me == null) return;
    _wanted = true;
    // 갱신 중이면 기다린다 — 건너뛰면 만료 토큰으로 붙는다(#299 와 같은 규칙).
    if (s.isRefreshing || s.isAccessExpiringSoon(skew: 60)) {
      await s.refreshOnce();
      if (!_wanted || s.user?.id != me) return; // 대기 중 로그아웃·계정 전환
    }
    final token = s.token;
    if (token == null) return; // 갱신 실패로 세션이 정리됐다
    await _c.realtime.setAuth(token); // 커스텀 JWT 로 realtime 인증(RLS 통과)
    if (!_wanted || _notif != null) return; // 이미 구독 중이거나 그만둔 뒤
    _subscribe(me);
  }

  void _subscribe(String me) {
    _retry?.cancel();
    _retry = null;
    final gen = ++_gen;
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
        .subscribe((status, err) {
          if (gen != _gen) return; // 이전 세대 채널의 뒤늦은 콜백
          if (status == RealtimeSubscribeStatus.subscribed) {
            _attempt = 0;
            return;
          }
          // channelError · timedOut · closed — 어느 쪽이든 이벤트가 안 온다.
          _onDropped(me, status, err);
        });
  }

  /// 구독이 끊겼다. 채널을 **반드시 비운다** — 남겨 두면 다음 start() 가 조기
  /// 리턴해 영영 재구독하지 않는다(이 수정의 핵심).
  void _onDropped(String me, RealtimeSubscribeStatus status, Object? err) {
    _gen++; // 이 채널의 이후 콜백은 전부 무시
    final dead = _notif;
    _notif = null;
    if (dead != null) _c.removeChannel(dead);

    if (!_wanted) return; // stop() 으로 우리가 끊은 것 — 재구독하지 않는다

    _attempt++;
    final delay = realtimeRetryDelay(_attempt);
    final e = err ?? StateError('realtime ${status.name}');
    final where = 'realtime.subscribe';
    // 첫 실패만 서버로 올린다(reported). 이후 재시도까지 보내면 끊긴 동안
    // client_errors 가 같은 사건으로 채워진다 — 분당 상한도 그걸로 소모된다.
    if (_attempt == 1) {
      ErrorReporter.report(
        e,
        where: where,
        extra: {'status': status.name, 'retry_in_sec': delay.inSeconds},
      );
    } else {
      ErrorReporter.ignored(
        e,
        where: where,
        why: '재구독 대기 중($_attempt회차, ${delay.inSeconds}초 후) — 첫 실패는 이미 보고됨',
      );
    }

    _retry = Timer(delay, () async {
      // 대기 중에 로그아웃했거나 다른 경로로 이미 붙었으면 그만둔다.
      if (!_wanted || _notif != null) return;
      final s = SessionManager.instance;
      if (s.user?.id != me) return; // 계정이 바뀌었다
      // 재시도 전에 소켓 인증을 현재 세션 기준으로 되돌린다 — 끊겨 있던 동안
      // access 가 만료됐을 수 있다(iOS 장기 백그라운드 복귀 실사고: 2.3일 지난
      // 토큰으로 재구독 → InvalidJWTToken). REST 는 관문(accessToken 콜백)이
      // 갱신해 주지만 realtime 소켓 auth 는 setAuth 를 다시 불러야만 바뀐다.
      // 갱신 중이면 **기다린다.** 건너뛰면 그 사이 요청이 만료 토큰으로 나간다
      // (#299 에서 accessToken 콜백을 같은 이유로 고쳤다).
      if (s.isRefreshing || s.isAccessExpiringSoon(skew: 60)) {
        await s.refreshOnce();
        if (!_wanted || _notif != null || s.user?.id != me) return;
      }
      final token = s.token;
      if (token == null) return; // 갱신 실패로 세션이 정리됐다 — 재구독 무의미
      await _c.realtime.setAuth(token);
      if (!_wanted || _notif != null) return;
      _subscribe(me);
    });
  }

  /// 로그아웃/세션 무효화 시 — 구독 해제. 예약된 재시도도 함께 취소한다.
  void stop() {
    _wanted = false; // removeChannel 이 부르는 closed 콜백이 재구독하지 않게 먼저.
    _gen++;
    _attempt = 0;
    _retry?.cancel();
    _retry = null;
    if (_notif != null) {
      _c.removeChannel(_notif!);
      _notif = null;
    }
  }
}
