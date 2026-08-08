/// 앱 부트스트랩 — **띄우기 전에 세워야 하는 것들**을 순서대로 세운다.
///
/// main.dart 에서 떼어낸 이유는 길이가 아니라 **섞여 있었기 때문**이다. 한 파일에
/// ① 초기화 순서 ② 푸시 탭 라우팅 ③ 앱 위젯이 함께 있어서, 초기화 순서를 고치려면
/// 라우팅 코드를 지나쳐야 했고 그 반대도 마찬가지였다.
///
/// ⚠️ **순서가 곧 계약이다.** 아래 단계는 서로를 전제한다:
///   · 세션 복원이 Supabase 초기화보다 **먼저** — accessToken 콜백이 세션을 읽는다.
///   · Observability.bootstrap 이 runApp 을 부른다 — 오류 보고를 먼저 세우고 앱을 띄운다.
///   · 푸시(FCM)는 **마지막에, await 없이** — iOS 권한 다이얼로그/APNs 미설정에서
///     블록될 수 있어 await 하면 흰 화면에서 멈춘다.
/// 순서를 바꿀 때는 각 단계 주석의 근거를 먼저 읽을 것.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../firebase_options.dart';
import '../services/local_notice_service.dart';
import '../services/observability.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import '../services/theme_controller.dart';
import '../utils/firebase_web_sdk.dart';
import 'pawmate_app.dart';
import 'push_routing.dart';

abstract final class AppBootstrap {
  /// 엔진 초기화부터 runApp 까지. main() 은 이것만 부른다.
  static Future<void> run() async {
    // Flutter 엔진 초기화
    WidgetsFlutterBinding.ensureInitialized();

    // 상태바 기본값 — 앱 배경이 밝으므로 아이콘(시간·배터리·네트워크)을 어둡게.
    // 사진 히어로 화면은 각자 AnnotatedRegion 으로 밝게 덮고, 벗어나면 자동 복원.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Android
        statusBarBrightness: Brightness.light, // iOS
      ),
    );

    // 저장된 로그인 세션 복원
    await SessionManager.instance.load();

    // 저장된 테마 모드(시스템/라이트/다크) 복원.
    await ThemeController.load();

    // 네이버 지도 SDK 초기화 (NCP Maps 신규 인증 - Client ID)
    // 웹은 지도 탭 자체가 없다(docs/web-port.md) — 플러그인이 웹 구현을 갖고 있지
    // 않아 여기서 던지면 runApp 전에 죽어 흰 화면이 된다.
    if (!kIsWeb) {
      await FlutterNaverMap().init(
        clientId: Env.naverMapClientId,
        onAuthFailed: (ex) {
          switch (ex) {
            case NQuotaExceededException(:final message):
              debugPrint('네이버 지도 사용량 초과: $message');
            case NUnauthorizedClientException() ||
                NClientUnspecifiedException() ||
                NAnotherAuthFailedException():
              debugPrint('네이버 지도 인증 실패: $ex');
          }
        },
      );
    }

    // Supabase 연결
    // publishableKey(공개 키)만 클라이언트에 둔다. service_role 키는 절대 포함 금지.
    // 프로젝트/환경 전환은 lib/env.dart 의 --dart-define 오버라이드로.
    // accessToken: 로그인 시 발급된 커스텀 JWT 를 모든 요청 Authorization 에 첨부 →
    // RLS 의 app.uid() 가 JWT 의 sub(user_id)를 읽는다. 비로그인 시 null → anon 으로 동작.
    // 매 요청 전 호출되므로 access 만료 임박 시 여기서 refresh 로 무중단 갱신(단일비행).
    //  · isRefreshing 중엔 재진입 금지 — refresh 엔드포인트 호출도 이 콜백을 거치므로
    //    무한재귀/데드락을 막는다(refresh 는 verify_jwt=false 라 stale access 로도 무해).
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      accessToken: () async {
        final s = SessionManager.instance;
        // 갱신이 이미 돌고 있으면 **그것을 기다린다.** 종전에는 `!isRefreshing`
        // 으로 건너뛰었는데, 그러면 그 요청은 만료된 토큰을 달고 나간다 —
        // 첫 실행에서 커뮤니티·채팅·내정보가 동시에 로드를 걸면 하나만 성공하고
        // 나머지는 401 로 새로고침 버튼이 떴다. refreshOnce 는 단일비행이라
        // 여럿이 기다려도 갱신은 한 번이다.
        //
        // 기다려도 교착이 아닌 이유: refresh 호출은 Supabase 클라이언트가 아니라
        // 순수 http 로 나가므로 이 콜백을 다시 타지 않는다(session.dart 참고).
        if (s.isRefreshing || s.isAccessExpiringSoon(skew: 60)) {
          await s.refreshOnce();
        }
        // 갱신할 수단이 없는데 이미 만료됐다면 여기서 끊는다(#231).
        //
        // 이 콜백은 **모든 요청이 지나가는 유일한 관문**이라, 앱에 없던 "전역 401
        // 핸들러" 자리가 사실 여기였다. 예전엔 만료된 토큰을 그대로 첨부했고,
        // 그러면 모든 요청이 401 → 화면마다 "불러오지 못했어요" 만 무한 반복되는데
        // 앱은 로그인된 UI 를 그린 채 굳는다. 웹은 refresh 를 저장하지 않으므로
        // (결정 7) 8시간 뒤 **확정적으로** 이 상태가 됐다.
        //
        // 라우팅은 onInvalidated 가 맡는다. 이 호출을 await 하지 않는 이유는
        // 요청을 붙잡아 두지 않기 위해서다 — 아래에서 null 을 돌려주면 그 요청은
        // anon 으로 나가 어차피 거절된다.
        if (s.isDeadSession) {
          unawaited(s.invalidateIfDead());
          return null;
        }
        // 간이 회원(후기 전용) 토큰은 정식 세션이 없을 때만 쓰인다 — 갱신 대상도
        // 아니고 저장되지도 않는다(SessionManager.beginLiteSession 참고).
        return s.token ?? s.liteToken;
      },
      // 스토리지 업로드 진행률을 얻기 위한 얇은 래퍼. 감시 중인 경로가 없으면
      // 원 클라이언트로 그대로 흘려보내므로 나머지 트래픽에는 영향이 없다.
      httpClient: StorageService.uploadProgress,
    );

    // 포그라운드 알림 — 알림 실시간 구독(realtime) 기반. FCM 포그라운드 푸시가 아니라
    // 이 경로를 쓴다: 푸시는 기기 토큰이 없으면(시뮬레이터·미등록) 조용히 스킵되지만
    // realtime 은 앱이 켜져 있는 한 항상 도착한다. 표시는 토스트가 아니라
    // 백그라운드 푸시와 동일한 OS 시스템 알림(LocalNoticeService).
    RealtimeService.instance.onNotificationBanner = showNotificationBanner;
    LocalNoticeService.instance.onTap = (type, resourceType, resourceId) {
      unawaited(openFromPush(type, resourceType, resourceId));
    };
    unawaited(LocalNoticeService.instance.init());

    // 로그인 상태면 realtime 재인증 + 알림 실시간 구독(벨/목록/채팅 목록 라이브 갱신).
    if (SessionManager.instance.isLoggedIn) RealtimeService.instance.start();

    // runApp 을 직접 부르지 않는다 — 오류 보고를 먼저 세운 뒤 앱을 띄운다.
    // (SENTRY_DSN 미설정이면 종전과 동일하게 곧바로 runApp — Observability 참고)
    await Observability.bootstrap(const PawMateApp());

    // 웹도 푸시를 쓴다(Phase D) — 서비스워커(web/firebase-messaging-sw.js) + VAPID.
    // iOS Safari 는 **홈 화면에 추가(PWA 설치)한 상태에서만** 수신한다. 일반 탭에서는
    // 권한 요청 자체가 실패하는데, PushService 가 예외를 삼키므로 무해하다.
    //
    // OS 푸시(FCM) 초기화는 앱 시작(runApp)을 막지 않도록 백그라운드로.
    // (init 이 iOS 권한 다이얼로그 응답 대기 + APNs 미설정 getToken 에서 블록될 수 있어,
    //  await 하면 흰 화면에서 멈춘다.)
    unawaited(_setupPush());
  }
}

Future<void> _setupPush() async {
  try {
    // 웹은 Firebase JS SDK 를 우리가 먼저 로드한다(CSP — web/firebase-sdk.js).
    // 이 대기를 빼면 초기화가 로드를 앞질러 플러그인의 인라인 주입 경로로 새고,
    // 그 인라인은 CSP 에 막혀 있어 푸시가 조용히 죽는다.
    await ensureFirebaseSdkReady();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    PushService.instance.onOpen = (type, resourceType, resourceId) {
      unawaited(openFromPush(type, resourceType, resourceId));
    };
    await PushService.instance.init();
  } catch (e) {
    debugPrint('푸시 초기화 건너뜀(Firebase/APNs 미설정?): $e');
  }
}
