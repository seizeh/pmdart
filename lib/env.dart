/// 클라이언트에 두는 공개 키/식별자 모음 — 빌드 시 --dart-define 으로 덮어쓴다.
///
/// 여기의 값은 전부 클라이언트 배포본에 포함되어도 안전한 publishable(공개) 값이다.
/// 진짜 비밀(service_role·JWT secret·SMS 키 등)은 서버(Edge Function 시크릿)에만
/// 존재하며 이 파일에 추가해선 안 된다.
///
/// 다른 Supabase 프로젝트/환경으로 빌드할 때:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
library;

abstract final class Env {
  /// Supabase 프로젝트 URL.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vyatppuxmpulqtxevfpk.supabase.co',
  );

  /// Supabase publishable 키(공개용 — RLS 가 전제인 anon 접근 키).
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_T3dPO3-WMtkFDF_z5VIBBw_NKHwi-ZZ',
  );

  /// 네이버 지도(NCP Maps) Client ID — 콘솔에서 번들/패키지로 제한된 공개 식별자.
  static const naverMapClientId = String.fromEnvironment(
    'NAVER_MAP_CLIENT_ID',
    defaultValue: 'cy02y6r0d5',
  );

  /// 스토어 주소 — 웹에서 앱 전용 기능(지도·채팅)을 누르면 여기로 보낸다.
  /// **미설정이 기본**이다(출시 전). 비어 있으면 설치 버튼 대신 "출시 준비 중"
  /// 안내를 보여준다 — 죽은 링크를 노출하지 않기 위한 스위치.
  /// share-view Edge Function 의 STORE_URL_IOS/ANDROID 와 같은 값을 넣는다.
  static const storeUrlIos = String.fromEnvironment('STORE_URL_IOS');
  static const storeUrlAndroid = String.fromEnvironment('STORE_URL_ANDROID');

  /// 행안부 juso.go.kr confmKey(클라이언트 키). 위의 값들과 달리 콘솔에서
  /// 앱 단위로 제한할 수 없고 쿼터 소진·남용 여지가 있어 **기본값을 두지 않는다**
  /// — 빌드 시 --dart-define=JUSO_API_KEY=... 로 주입한다.
  /// 비우면 주소 검색이 비활성화되고 업체등록 화면이 수동 입력으로 폴백한다.
  static const jusoApiKey = String.fromEnvironment('JUSO_API_KEY');

  /// 웹 푸시(FCM) VAPID **공개** 키 — Firebase 콘솔의 '웹 푸시 인증서' 키 쌍.
  ///
  /// 공개값이 맞다. 비밀키는 Firebase 가 갖고 있고, 이 공개키는 원래 클라이언트
  /// 번들에 실려 브라우저가 구독을 만들 때 쓰인다(supabasePublishableKey 와 같은 급).
  ///
  /// 비어 있으면 **웹 푸시를 통째로 건너뛴다** — 알림 권한 팝업만 뜨고 토큰은 못 받는
  /// 어중간한 상태를 만들지 않기 위한 스위치다(storeUrl* 와 같은 관용구).
  /// 웹이 아닌 플랫폼에서는 쓰이지 않는다.
  static const webPushVapidKey = String.fromEnvironment(
    'WEB_PUSH_VAPID_KEY',
    defaultValue:
        'BAvGbYzuiBHUJCDSanC43cgKrt4gRMUwqHtm25RjsC93znXwpcO9xlIdG5U9A1CtjuBwMITyPzaNLWygkifNJZc',
  );

  /// 릴리스 식별자(`pawmate@2.0.0+10` 형태) — 오류 보고에 함께 저장해
  /// '어느 배포부터 생긴 오류인지' 를 본다(app.client_errors.app_release).
  /// 웹은 deploy-web.yml 이 pubspec 버전에서 뽑아 주입한다.
  static const appRelease = String.fromEnvironment('APP_RELEASE');

  /// 디버그 빌드에서도 오류를 서버(`app.client_errors`)로 보낼지.
  ///
  /// 기본값이 false 인 이유: 디버그 빌드는 개발 중 오류를 대량으로 뿜는다(위젯
  /// 어서션 하나가 리빌드마다 반복 보고된다). 그게 운영 테이블에 섞이면 실사용자
  /// 오류가 노이즈에 묻힌다. 평소 디버그에서는 콘솔(DebugErrorSink)로 충분하다.
  ///
  /// 전송 경로 자체를 검증할 때만 켠다:
  /// `flutter run --dart-define=REPORT_ERRORS_IN_DEBUG=true`
  static const reportErrorsInDebug = bool.fromEnvironment(
    'REPORT_ERRORS_IN_DEBUG',
  );
}
