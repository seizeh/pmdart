import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../models/community.dart' show Post;
import '../motion/motion.dart';
import '../screen/admin/admin_home_screen.dart';
import '../screen/facility_review_screen.dart';
import '../screen/main_screen.dart';
import '../screen/post_detail_screen.dart';
import '../screen/user_profile_screen.dart';
import '../screen/welcome_screen.dart';
import '../services/app_events.dart';
import '../services/community/post_query_repository.dart';
import '../services/facility_repository.dart';
import '../services/keyboard_barrier.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import '../services/session.dart';
import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import '../utils/web_link.dart';
import '../widgets/app_scroll_behavior.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_toast.dart';
import 'app_keys.dart';

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
    // 그 **직전**에 — 아직 토큰이 살아 있을 때 서버측 푸시 토큰을 해제한다.
    // onInvalidated 안에서 하면 이미 clear 가 끝나 `isLoggedIn` 가드에 걸려
    // 서버 해제가 통째로 스킵된다(#237 의 "서버 먼저, 기기 나중" 역전).
    SessionManager.instance.onBeforeInvalidate =
        PushService.instance.clearToken;
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
    final userId = initialSharedUserId();
    final reviewFacilityId = initialReviewFacilityId();
    if (postId == null && userId == null && reviewFacilityId == null) return;

    // 네비게이터 준비 대기 — 첫 프레임 직후라 보통 바로 있지만 없으면 잠깐 기다린다
    // (openFromPush 와 같은 방어).
    NavigatorState? nav = navigatorKey.currentState;
    for (var i = 0; i < 20 && nav == null; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      nav = navigatorKey.currentState;
    }
    if (nav == null || !mounted) return;

    // 매장 QR(`/r/<facilityId>`) — 그 매장의 후기 작성 화면을 바로 연다.
    if (reviewFacilityId != null) {
      await _openReviewWrite(nav, reviewFacilityId);
      return;
    }

    // 업체 프로필(`/u/<userId>`). 게시글과 달리 선조회를 하지 않는다: 프로필 화면이
    // 스스로 로드하며 실패 표시까지 처리하고, 여기서 한 번 더 받아봐야 첫 화면만 늦어진다.
    if (userId != null) {
      _openSharedProfile(nav, userId);
      return;
    }
    // 위에서 userId 를 처리하고 돌아갔으므로 여기 오면 postId 는 반드시 있다.
    final sharedPostId = postId!;

    // 콜드 로드에서는 번들·wasm 다운로드와 겹쳐 첫 요청이 일시 실패하곤 한다.
    // 한 번 실패했다고 포기하면 공유 링크가 **조용히 피드로 떨어진다**(실제로
    // 간헐 발생을 목격). 예외일 때만 재시도하고, 결과가 null(삭제·비공개)이면
    // 재시도해봐야 소용없으므로 바로 빠진다.
    Post? loaded;
    var failed = false;
    for (var i = 0; i < 3; i++) {
      try {
        loaded = await PostQueryRepository.instance.fetchPost(sharedPostId);
        failed = false;
        break;
      } catch (e) {
        failed = true;
        debugPrint('공유 링크: 게시글 조회 실패(${i + 1}/3) — $e');
        if (i < 2) await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    if (!mounted) return;

    // final 로 받아야 아래 클로저에서 널 프로모션이 유지된다(캡처된 지역변수는
    // 승격이 풀려 dart2js 가 거부한다 — analyzer 만으로는 안 잡힌다).
    final post = loaded;
    if (post == null) {
      // 말없이 피드로 떨구지 않는다 — 왜 안 열렸는지 알려준다.
      final overlay = nav.overlay;
      if (overlay != null) {
        AppToast.show(
          overlay,
          failed ? '게시글을 불러오지 못했어요' : '삭제되었거나 볼 수 없는 게시글이에요',
        );
      }
      return;
    }

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

  /// 매장 QR 로 들어와 그 매장의 후기 작성 화면을 연다.
  ///
  /// 시설은 업체 계정이 없어도 존재하므로(공공데이터), 인증 전 매장에 뿌린 QR 도
  /// 그대로 동작한다. 비로그인이면 작성 화면이 게시 시점에 간이 인증을 청한다.
  ///
  /// 뒤로 가면 게스트 메인(커뮤니티)이 남도록 그 위에 얹는다 — 후기를 안 쓰기로
  /// 해도 앱을 둘러보는 쪽으로 이어져야 한다.
  Future<void> _openReviewWrite(NavigatorState nav, String facilityId) async {
    Facility? facility;
    try {
      facility = await FacilityRepository.instance.fetchById(facilityId);
    } catch (e) {
      debugPrint('매장 QR: 시설 조회 실패 — $e');
    }
    if (!mounted) return;

    if (!SessionManager.instance.isLoggedIn) {
      nav.pushAndRemoveUntil(
        AppPageRoute(builder: (_) => const MainScreen(isGuest: true)),
        (route) => false,
      );
    }

    final f = facility;
    if (f == null) {
      final overlay = nav.overlay;
      if (overlay != null) AppToast.show(overlay, '매장 정보를 불러오지 못했어요');
      return;
    }
    final rctx = nav.context;
    nav.push(
      CollapseRoute(
        builder: (_) =>
            FacilityReviewScreen(facility: f, originRect: riseOriginRect(rctx)),
      ),
    );
  }

  /// 매장 QR 로 들어온 업체 프로필을 연다.
  ///
  /// 게시글 공유와 같은 이유로 비로그인도 통과시키고, 게스트면 웰컴 대신 게스트
  /// 메인을 깐 뒤 그 위에 얹는다 — 프로필을 닫았을 때 웰컴으로 튕기지 않고
  /// 둘러보기로 이어져야 한다.
  ///
  /// 업체 얼굴로 연다(forcePersonalFace=false). QR 은 매장에서 나눠주는 물건이라
  /// 맥락이 명백히 업체고, 개인 얼굴로 열면 후기 작성 버튼이 뜨지 않는다.
  void _openSharedProfile(NavigatorState nav, String userId) {
    if (!SessionManager.instance.isLoggedIn) {
      nav.pushAndRemoveUntil(
        AppPageRoute(builder: (_) => const MainScreen(isGuest: true)),
        (route) => false,
      );
    }
    nav.push(CollapseRoute(builder: (_) => UserProfileScreen(userId: userId)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    } else if (state == AppLifecycleState.paused) {
      // 백그라운드에선 실시간 소켓을 끊는다 → 배터리 절약 + OEM 강제종료 회피.
      RealtimeService.instance.stop();
    }
  }

  /// 포그라운드 복귀 처리(#236).
  ///
  /// 예전엔 세 줄이 순서 없이 나란히 있었고 둘 다 어긋났다.
  ///
  /// ① **만료 토큰으로 realtime 재인증** — `checkAlive` 를 await 하지 않은 채
  ///    `RealtimeService.start()` 가 저장된(=갱신 안 된) 토큰으로 `setAuth` 를 했다.
  ///    8시간 넘게 백그라운드에 있었다면 그 토큰은 만료다. 알림 채널이 만료 JWT 로
  ///    구독돼 아무것도 못 받고, 회복은 다음 REST 호출의 refresh 부수효과에 의존했다.
  ///    → 세션 확인(필요하면 갱신까지)을 **await 한 뒤** realtime 을 켠다.
  ///
  /// ② **복귀 시 재동기화 부재** — 벨 배지와 채팅 목록은 각각 `AppEvents` 에만
  ///    반응하는데, 백그라운드 중 도착한 것들은 그 이벤트를 못 봤다. 트레이에는
  ///    푸시 5개가 쌓였는데 앱을 열면 배지가 이전 값 그대로였다.
  ///    → 복귀 시 두 이벤트를 한 번 쏴서 강제 재조회.
  Future<void> _onResumed() async {
    final s = SessionManager.instance;
    if (s.isLoggedIn) {
      // 만료 임박이면 여기서 갱신된다(단일비행). 죽은 세션이면 checkAlive 가
      // 정리하고 onInvalidated 로 로그인 화면으로 보낸다(#231).
      final dead = await s.checkAliveAndClearIfDead();
      if (dead) return; // 로그아웃됐으면 아래 재개·재동기화는 의미 없다
      if (s.isAccessExpiringSoon(skew: 60)) await s.refreshOnce();
      RealtimeService.instance.start();
    }
    // 백그라운드 동안 쌓인 것을 화면에 반영 — 로그인 여부와 무관하게 안전하다
    // (구독자들이 각자 게스트 여부를 판단한다).
    AppEvents.instance.notifyNotification();
    AppEvents.instance.notifyChat();
  }

  void _handleInvalidated() {
    RealtimeService.instance.stop();
    // 푸시 토큰 해제는 onBeforeInvalidate 로 옮겼다 — 여기서 부르면 세션이 이미
    // 지워져 있어 서버 해제가 스킵되고 기기측 삭제만 됐다(initState 주석 참고).
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
        // 웹만: 데스크톱 스크롤바 숨김 + 마우스 드래그 허용(가로 칩 목록 도달).
        scrollBehavior: kIsWeb ? const WebScrollBehavior() : null,
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
