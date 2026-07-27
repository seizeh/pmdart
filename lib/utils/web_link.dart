/// 웹 진입 URL 파싱 — 공유 링크에서 넘어온 딥링크를 읽는다.
///
/// 동선: 카톡 등에 공유된 `go.pawmate.kr/s?t=<token>` (서버 렌더링 미리보기,
/// OG 태그·퍼널 계측 유지) → "웹에서 계속 보기" CTA → `app.pawmate.kr/p/<postId>`.
/// 토큰이 아니라 **게시글 id** 로 넘어오는 이유: `share_view_load` 는
/// service_role 전용이라 웹앱(anon)이 토큰을 못 읽는다. 반면 게시글 자체는
/// `v_post_feed` 로 이미 anon 열람 가능하다(비로그인 둘러보기와 같은 경로).
/// 자세한 내용은 docs/web-port.md 결정 6.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_link_meta.dart';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// 이번 진입에서 열어야 할 게시글 id. 두 경로를 지원한다.
///
///  1. 주소 `/p/<uuid>` — 웹앱 주소를 직접 열었을 때.
///  2. `<meta name="pm-post">` — 공유 링크(`go.pawmate.kr/s?t=…`)가 셸에 심어
///     보낸 값. 주소에는 토큰만 있고 토큰→게시글 해석은 웹앱이 못 하므로
///     서버가 대신 실어 보낸다([web_link_meta.dart]).
///
/// `--base-href` 로 하위 경로에 배포될 수 있어 앞에서부터 세지 않고 `p` 세그먼트를
/// 뒤에서 찾는다. uuid 형태가 아니면 무시한다(잘못된 링크로 요청을 낭비하지 않게).
String? initialSharedPostId() {
  if (!kIsWeb) return null;
  final fromPath = sharedPostIdOf(Uri.base);
  if (fromPath != null) return fromPath;
  final injected = injectedPostId();
  return (injected != null && _uuid.hasMatch(injected)) ? injected : null;
}

/// [initialSharedPostId] 의 순수 함수 버전 — 테스트용.
String? sharedPostIdOf(Uri uri) {
  final seg = uri.pathSegments;
  final i = seg.lastIndexOf('p');
  if (i < 0 || i + 1 >= seg.length) return null;
  final id = seg[i + 1];
  return _uuid.hasMatch(id) ? id : null;
}
