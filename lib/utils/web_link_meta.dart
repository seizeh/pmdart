/// 공유 링크가 HTML 에 심어 보낸 게시글 id 를 읽는다.
///
/// `go.pawmate.kr/s?t=<token>` 은 share-view Edge Function 이 **웹앱 셸을 그대로
/// 내려주되** 토큰별 OG 메타와 `<meta name="pm-post" content="<uuid>">` 를 주입한
/// 형태다(docs/web-port.md 결정 6). 주소에는 토큰만 있고 게시글 id 가 없으므로
/// (토큰→게시글 해석은 service_role 전용이라 웹앱이 못 한다) 이 메타로 받는다.
library;

export 'web_link_meta_io.dart'
    if (dart.library.js_interop) 'web_link_meta_web.dart';
