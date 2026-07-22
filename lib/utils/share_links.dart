/// 공유 뷰어(share-view) 공개 주소 (0028 §3).
///
/// supabase.co 직결 주소는 절대 외부 노출 금지 — 게이트웨이가 HTML 을 차단해
/// 소스가 그대로 보인다(0028 §3.1 4차 개정). QR·카톡 링크 등 모든 외부 노출은
/// 자체 도메인(Cloudflare Worker 프록시, pmdb workers/share-proxy)만 쓴다.
const kShareViewBase = 'https://go.pawmate.kr/s';

String shareViewUrl(String token) => '$kShareViewBase?t=$token';
