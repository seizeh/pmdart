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

  /// 행안부 juso.go.kr confmKey(클라이언트 키). 비우면 주소 검색이 비활성화되고
  /// 업체등록 화면이 수동 입력으로 폴백한다.
  static const jusoApiKey = String.fromEnvironment(
    'JUSO_API_KEY',
    defaultValue: 'U01TX0FVVEgyMDI2MDcxNDE2MDExMTExOTcyMzE=',
  );
}
