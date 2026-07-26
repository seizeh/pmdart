import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'firebase_options.dart';
import 'models/community.dart' show Post;
import 'motion/motion.dart';
import 'screen/activity_screens.dart' show MyReviewsScreen;
import 'screen/admin/admin_home_screen.dart';
import 'screen/chat_room_screen.dart';
import 'screen/guardian_invites_screen.dart';
import 'screen/main_screen.dart';
import 'screen/notifications_screen.dart';
import 'screen/post_detail_screen.dart';
import 'screen/review_detail_screen.dart';
import 'screen/user_profile_screen.dart';
import 'screen/vaccination_schedule_screen.dart';
import 'screen/welcome_screen.dart';
import 'services/chat_repository.dart';
import 'services/community_repository.dart';
import 'services/facility_review_repository.dart';
import 'services/keyboard_barrier.dart';
import 'services/local_notice_service.dart';
import 'services/pet_repository.dart';
import 'services/push_service.dart';
import 'services/realtime_service.dart';
import 'services/session.dart';
import 'services/theme_controller.dart';
import 'theme/app_theme.dart';
import 'utils/web_link.dart';
import 'widgets/app_shell.dart';
import 'widgets/app_toast.dart';
import 'widgets/review_cards.dart';

/// 강제 로그아웃(세션 무효화) 시 라우팅·안내를 위한 전역 키.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
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
      if (!s.isRefreshing && s.isAccessExpiringSoon(skew: 60)) {
        await s.refreshOnce();
      }
      return s.token;
    },
  );

  // 포그라운드 알림 — 알림 실시간 구독(realtime) 기반. FCM 포그라운드 푸시가 아니라
  // 이 경로를 쓴다: 푸시는 기기 토큰이 없으면(시뮬레이터·미등록) 조용히 스킵되지만
  // realtime 은 앱이 켜져 있는 한 항상 도착한다. 표시는 토스트가 아니라
  // 백그라운드 푸시와 동일한 OS 시스템 알림(LocalNoticeService).
  RealtimeService.instance.onNotificationBanner = _showNotificationBanner;
  LocalNoticeService.instance.onTap = (type, resourceType, resourceId) {
    unawaited(openFromPush(type, resourceType, resourceId));
  };
  unawaited(LocalNoticeService.instance.init());

  // 로그인 상태면 realtime 재인증 + 알림 실시간 구독(벨/목록/채팅 목록 라이브 갱신).
  if (SessionManager.instance.isLoggedIn) RealtimeService.instance.start();

  runApp(const PawMateApp());

  // 웹은 OS 푸시를 쓰지 않는다 — 서비스워커·VAPID 세팅이 필요하고 iOS Safari 는
  // PWA 설치 상태에서만 수신된다. 웹 푸시는 Phase D(docs/web-port.md).
  if (kIsWeb) return;

  // OS 푸시(FCM) 초기화는 앱 시작(runApp)을 막지 않도록 백그라운드로.
  // (init 이 iOS 권한 다이얼로그 응답 대기 + APNs 미설정 getToken 에서 블록될 수 있어,
  //  await 하면 흰 화면에서 멈춘다.)
  unawaited(_setupPush());
}

/// 포그라운드 알림(Android) — 새 알림(realtime)이 오면 백그라운드 푸시와 동일한
/// 형태의 OS 시스템 알림으로 보여주고, 탭하면 해당 화면으로 이동한다.
/// iOS 는 FCM 의 네이티브 포그라운드 배너가 담당(LocalNoticeService 는 no-op).
void _showNotificationBanner(Map<String, dynamic> row) {
  final type = (row['notification_type'] ?? '') as String;
  final resourceType = row['resource_type'] as String?;
  final resourceId = row['resource_id'] as String?;
  // 동기화용 타입은 사용자 대면 알림이 아님.
  if (type == 'chat_read_receipt' || type == 'unread_sync') return;
  // 포그라운드에서만 — 백그라운드 전환 직후 realtime 이 잠시 살아 있으면
  // FCM 푸시(OS 표시)와 이중 알림이 되므로 그쪽에 맡긴다.
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    return;
  }
  // 지금 보고 있는 채팅방의 메시지면 생략 — 이미 화면에 실시간으로 뜬다.
  if (type == 'chat_message' &&
      resourceId != null &&
      ChatRepository.instance.activeRoomId == resourceId) {
    return;
  }
  unawaited(
    LocalNoticeService.instance.show(
      title: row['title'] as String?,
      body: row['body'] as String?,
      type: type,
      resourceType: resourceType,
      resourceId: resourceId,
    ),
  );
}

/// 푸시 탭 라우팅 — 대상 화면(채팅방/게시글/후기/초대함)으로 **바로** 이동한다.
/// 종료 상태에서 탭해 콜드 스타트해도 동일(네비게이터·세션 준비를 기다린 뒤 이동).
/// 대상을 못 찾으면(삭제·네트워크 실패 등) 알림함으로 폴백.
/// 알림함(벨 패널·알림 화면)도 이 라우팅을 그대로 쓴다 — 채팅방은 채팅 탭 위에
/// rise 전환으로 열려, 닫으면(쓸어내리기/뒤로가기) 채팅 목록이 나온다.
Future<void> openFromPush(
  String type,
  String? resourceType,
  String? resourceId, {
  // 알림함(목록/패널)에서의 탭은 false — 라우팅할 곳이 없으면 아무것도 하지
  // 않는다(알림함 안에서 알림함을 또 여는 재귀 방지). 푸시 탭은 기본 true.
  bool fallbackToInbox = true,
}) async {
  debugPrint('deeplink: type=$type resource=$resourceType/$resourceId');
  // 콜드 스타트 — 첫 프레임(네비게이터)이 붙을 때까지 잠깐 대기(최대 5초).
  NavigatorState? nav = navigatorKey.currentState;
  for (var i = 0; i < 50 && nav == null; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    nav = navigatorKey.currentState;
  }
  if (nav == null) return;
  // 알림은 로그인 사용자에게만 온다 — 세션이 없으면(만료 등) 라우팅하지 않는다.
  if (!SessionManager.instance.isLoggedIn) return;

  // 딥링크는 항상 "루트(메인 탭) 위에 상세 1장" 스택으로 만든다 — 상세를 닫으면
  // (뒤로가기/쓸어내리기) 관련 탭(채팅 목록·커뮤니티 등)이 바로 나온다.
  void popToRoot() => nav!.popUntil((r) => r.isFirst);

  // 백그라운드 복귀 직후엔 끊긴 소켓 탓에 첫 요청이 일시 실패하곤 한다 —
  // 대상 조회는 짧게 재시도해 '탭했는데 알림함 폴백'으로 새지 않게 한다.
  Future<T?> fetchRetry<T>(Future<T?> Function() f) async {
    for (var i = 0; i < 3; i++) {
      try {
        final r = await f();
        if (r != null) return r;
      } catch (e) {
        debugPrint('push route: 대상 조회 실패(${i + 1}/3) — $e');
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  try {
    if (type == 'guardian_invite') {
      // 초대 알림은 리소스 없이 초대함으로.
      popToRoot();
      nav.push(AppPageRoute(builder: (_) => const GuardianInvitesScreen()));
      return;
    }
    if (type == 'review_received') {
      // 후기 알림 — 내가 받은 후기 화면으로.
      popToRoot();
      nav.push(AppPageRoute(builder: (_) => const MyReviewsScreen()));
      return;
    }
    if (resourceId != null && resourceId.isNotEmpty) {
      switch (resourceType) {
        case 'post':
          final post = await fetchRetry(
            () => CommunityRepository.instance.fetchPost(resourceId),
          );
          if (post != null) {
            popToRoot();
            MainScreen.tabRequest.value = MainScreen.tabCommunity;
            // 앱 공통 상세 언어 — 아래에서 떠오르고, 쓸어내리면 닫힌다.
            final pctx = navigatorKey.currentContext;
            nav.push(
              CollapseRoute(
                builder: (_) => PostDetailScreen(
                  post: post,
                  originRect: pctx == null ? null : riseOriginRect(pctx),
                ),
              ),
            );
            return;
          }
        case 'user':
          // 포잉 알림 — 팔로우한 상대의 프로필로(개인 활동이라 개인 얼굴).
          popToRoot();
          final uctx = navigatorKey.currentContext;
          nav.push(
            CollapseRoute(
              builder: (_) => UserProfileScreen(
                userId: resourceId,
                forcePersonalFace: true,
                originRect: uctx == null ? null : riseOriginRect(uctx),
                cardRadius: 24,
              ),
            ),
          );
          return;
        case 'chat_room':
          final room = await fetchRetry(
            () => ChatRepository.instance.fetchRoom(resourceId),
          );
          if (room != null) {
            popToRoot();
            MainScreen.tabRequest.value = MainScreen.tabChat;
            // 채팅 목록에서 열 때와 동일한 언어 — 아래에서 떠오르고,
            // 헤더를 잡아 쓸어내리면 채팅 목록으로 닫힌다.
            final ctx = navigatorKey.currentContext;
            nav.push(
              CollapseRoute(
                builder: (_) => ChatRoomScreen(
                  room: room,
                  originRect: ctx == null ? null : riseOriginRect(ctx),
                ),
              ),
            );
            return;
          }
        case 'pet':
          // 접종 알림(vaccine_reminder) 등 펫 리소스 — 접종 일정 화면으로.
          // 펫 조회 실패(삭제·보호자 아님 등)면 아래 알림함 폴백.
          final pet = await fetchRetry(
            () => PetRepository.instance.fetchPet(resourceId),
          );
          if (pet != null) {
            popToRoot();
            nav.push(
              AppPageRoute(
                builder: (_) => VaccinationScheduleScreen(
                  petId: pet.id,
                  petName: pet.name,
                  birthDate: pet.birthDate,
                  speciesKind: pet.speciesKind,
                  source: 'manage',
                ),
              ),
            );
            return;
          }
        case 'facility_review':
          final review = await fetchRetry(
            () => FacilityReviewRepository.instance.fetchReviewById(resourceId),
          );
          if (review != null) {
            popToRoot();
            final rctx = navigatorKey.currentContext;
            nav.push(
              CollapseRoute(
                builder: (_) => ReviewDetailScreen(
                  review: ReviewCardData.fromFacilityReview(review),
                  originRect: rctx == null ? null : riseOriginRect(rctx),
                  fromDeepLink: true,
                ),
              ),
            );
            return;
          }
      }
    }
  } catch (_) {
    // 대상 조회 실패 — 아래 폴백으로.
  }
  // 대상 화면으로 못 갔으면 알림함으로(푸시 탭 한정 — 알림함 내 탭은 제자리 유지).
  if (fallbackToInbox) {
    popToRoot();
    nav.push(AppPageRoute(builder: (_) => const NotificationsScreen()));
  }
}

Future<void> _setupPush() async {
  try {
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

class PawMateApp extends StatefulWidget {
  const PawMateApp({super.key});

  @override
  State<PawMateApp> createState() => _PawMateAppState();
}

class _PawMateAppState extends State<PawMateApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 세션이 서버에서 무효화(타 기기 비번변경/정지·refresh 회수)되면 강제 로그아웃 라우팅.
    SessionManager.instance.onInvalidated = _handleInvalidated;
    // 시작 시 1회 세션 유효성 확인.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SessionManager.instance.checkAliveAndClearIfDead();
      unawaited(_openInitialWebLink());
    });
  }

  /// 공유 링크로 들어온 웹 진입(`/p/<postId>`) — 게시글 상세를 바로 연다.
  ///
  /// `openFromPush` 를 쓰지 않는 이유: 그쪽은 알림 라우팅이라 로그인 사용자
  /// 전용이다. 공유 링크는 **비로그인 열람이 목적**이므로(설치 전 가치, 0028
  /// 원칙 2) 게스트도 통과해야 한다.
  ///
  /// 비로그인이면 웰컴 화면 대신 게스트 메인을 깔고 그 위에 상세를 얹는다 —
  /// 상세를 닫았을 때 커뮤니티 피드가 나와야 둘러보기로 이어진다(웰컴으로
  /// 되돌아가면 거기서 끊긴다).
  Future<void> _openInitialWebLink() async {
    final postId = initialSharedPostId();
    if (postId == null) return;
    Post? loaded;
    try {
      loaded = await CommunityRepository.instance.fetchPost(postId);
    } catch (e) {
      // 네트워크 실패 등 — 조용히 평소 진입(웰컴/메인)으로 둔다.
      debugPrint('공유 링크: 게시글 조회 실패 — $e');
      return;
    }
    final nav = navigatorKey.currentState;
    // final 로 받아야 아래 클로저에서 널 프로모션이 유지된다(캡처된 지역변수는
    // 승격이 풀려 dart2js 가 거부한다 — analyzer 만으로는 안 잡힌다).
    final post = loaded;
    if (post == null || nav == null || !mounted) return;

    final guest = !SessionManager.instance.isLoggedIn;
    if (guest) {
      nav.pushAndRemoveUntil(
        AppPageRoute(builder: (_) => const MainScreen(isGuest: true)),
        (route) => false,
      );
    }
    // 앱 공통 상세 언어 — 아래에서 떠오르고, 쓸어내리면 닫힌다.
    nav.push(
      CollapseRoute(
        builder: (_) => PostDetailScreen(post: post, isGuest: guest),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 포그라운드 복귀 시 세션 유효성 재확인 → 무효면 즉시 로그아웃.
      SessionManager.instance.checkAliveAndClearIfDead();
      // 실시간 소켓 재개(백그라운드 알림은 FCM 이 담당하므로 손실 없음).
      if (SessionManager.instance.isLoggedIn) RealtimeService.instance.start();
    } else if (state == AppLifecycleState.paused) {
      // 백그라운드에선 실시간 소켓을 끊는다 → 배터리 절약 + OEM 강제종료 회피.
      RealtimeService.instance.stop();
    }
  }

  void _handleInvalidated() {
    RealtimeService.instance.stop();
    PushService.instance.clearToken(); // 무효화된 기기의 FCM 토큰도 삭제
    navigatorKey.currentState?.pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay != null) {
      AppToast.show(overlay, '다른 기기에서 로그인하거나 비밀번호가 변경되어 로그아웃되었어요. 다시 로그인해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) => MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        title: 'PawMate',
        debugShowCheckedModeBanner: false,
        // 머티리얼 위젯(날짜/시간 피커 등) 한국어화 — showDatePicker 는 이 로케일
        // 설정만으로 한국어(월/요일/버튼)로 표시된다.
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode, // 설정(내정보 수정 > 화면 테마)에서 변경·저장
        // 전 화면 공통 키보드 해제:
        //  · 스크롤: 하위 스크롤뷰의 드래그 시작을 받아 해제(알림은 계속 전파).
        //  · 탭: 키보드가 떠 있을 때만 전체 화면에 배리어를 깔아, 화면 탭을 '키보드 닫기'
        //    로 흡수(opaque)한다. 이 탭은 아래 위젯(게시글 등)에 전달되지 않으므로
        //    "키보드 닫으려다 게시글이 눌리는" 문제가 없다. 키보드가 없으면 배리어도
        //    없어 평소 탭은 정상 동작.
        builder: (context, child) {
          final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
          // 상태바 아이콘 기본값을 테마 밝기에 따라 — 개별 화면의 AnnotatedRegion
          // (사진 히어로 등)이 더 안쪽이라 필요한 곳은 여전히 덮어쓴다.
          final overlay = Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay,
            // 넓은 화면(데스크톱 웹)에서 본문을 폰 폭 컬럼으로 묶고 좌측 레일을
            // 둔다. 좁은 화면·네이티브에서는 통과만 한다(docs/web-port.md).
            // Navigator 바깥이라 상세 라우트가 얹혀도 컬럼·레일이 유지된다.
            child: AppShell(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // 세로 스크롤만 키보드를 닫는다 — 가로 스크롤(카테고리 칩 등 캐러셀)은
                  // 검색 도중의 필터 조작이므로 키보드·포커스를 유지해야 한다
                  // (닫으면 searchActive 가 풀려 칩이 함께 사라지는 문제).
                  if (n is ScrollStartNotification &&
                      n.dragDetails != null &&
                      n.metrics.axis == Axis.vertical) {
                    FocusManager.instance.primaryFocus?.unfocus();
                  }
                  return false;
                },
                child: ValueListenableBuilder<bool>(
                  valueListenable: keyboardBarrierEnabled,
                  builder: (_, barrierOn, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      child ?? const SizedBox.shrink(),
                      // 지도 등 자체 처리 화면(barrierOn=false)에서는 배리어를 끈다.
                      // translucent — 탭은 배리어가 아레나에서 먼저 이겨 '키보드 닫기'로
                      // 흡수하되(아래 위젯 안 눌림), 드래그는 아래로 통과해 스크롤이
                      // 정상 동작한다(스크롤 시작 시 위 리스너가 키보드를 닫음).
                      // opaque 였을 때 키보드가 뜬 동안 카테고리 칩 가로 스크롤 등
                      // 모든 스크롤이 먹통이 되던 문제 수정.
                      if (keyboardUp && barrierOn)
                        Positioned.fill(
                          // 예외 영역(카테고리 칩 등)은 배리어 히트 자체를 건너뛴다.
                          child: KeyboardBarrierHitFilter(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        home: !SessionManager.instance.isLoggedIn
            ? const WelcomeScreen()
            : SessionManager.instance.isAdmin
            ? const AdminHomeScreen()
            : const MainScreen(),
      ),
    );
  }
}
