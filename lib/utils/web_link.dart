/// 웹 진입 URL 파싱 — 공유 링크에서 넘어온 딥링크를 읽는다.
///
/// 동선: 카톡 등에 공유된 `go.pawmate.kr/s?t=<token>` 을 **사람이 열면** 서버가
/// `app.pawmate.kr/p/<postId>` 로 302 로 보낸다. 크롤러(UA 판별)에게는 OG 태그가
/// 든 서버 렌더링 HTML 을 그대로 줘서 링크 미리보기를 지킨다.
/// 토큰이 아니라 **게시글 id** 로 넘어오는 이유: `share_view_load` 는
/// service_role 전용이라 웹앱(anon)이 토큰을 못 읽는다. 반면 게시글 자체는
/// `v_post_feed` 로 이미 anon 열람 가능하다(비로그인 둘러보기와 같은 경로).
/// 자세한 내용은 docs/web-port.md 결정 6.
///
/// 매장 QR(`kind='facility_preview'`)은 같은 규칙으로 `/r/<facilityId>` — **그
/// 매장의 후기 작성 화면**으로 보낸다(0029). 손님이 QR 을 찍는 목적이 후기라
/// 미리보기를 거치지 않고 바로 연다.
///
/// 업체 프로필(`/u/<userId>`)도 함께 지원한다 — QR 은 쓰지 않지만 업체 계정을
/// 가리키는 공유 경로가 늘어날 때를 위한 것이다.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// 진입 URL 이 `/p/<postId>` 면 그 id, 아니면 null.
///
/// `--base-href` 로 하위 경로에 배포될 수 있어 앞에서부터 세지 않고 `p` 세그먼트를
/// 뒤에서 찾는다. uuid 형태가 아니면 무시한다(잘못된 링크로 요청을 낭비하지 않게).
String? initialSharedPostId() {
  if (!kIsWeb) return null;
  return sharedPostIdOf(Uri.base);
}

/// [initialSharedPostId] 의 순수 함수 버전 — 테스트용.
String? sharedPostIdOf(Uri uri) => _idAfter(uri, 'p');

/// 진입 URL 이 `/u/<userId>` 면 그 id, 아니면 null — 매장 QR 이 보내는 업체 프로필.
String? initialSharedUserId() {
  if (!kIsWeb) return null;
  return sharedUserIdOf(Uri.base);
}

/// [initialSharedUserId] 의 순수 함수 버전 — 테스트용.
String? sharedUserIdOf(Uri uri) => _idAfter(uri, 'u');

/// 진입 URL 이 `/r/<facilityId>` 면 그 id — 매장 QR 이 보내는 후기 작성 대상.
String? initialReviewFacilityId() {
  if (!kIsWeb) return null;
  return reviewFacilityIdOf(Uri.base);
}

/// [initialReviewFacilityId] 의 순수 함수 버전 — 테스트용.
String? reviewFacilityIdOf(Uri uri) => _idAfter(uri, 'r');

/// `<segment>/<uuid>` 를 뒤에서 찾아 uuid 를 돌려준다.
///
/// `--base-href` 로 하위 경로에 배포될 수 있어 앞에서부터 세지 않는다.
/// uuid 형태가 아니면 무시한다(잘못된 링크로 요청을 낭비하지 않게).
String? _idAfter(Uri uri, String segment) {
  final seg = uri.pathSegments;
  final i = seg.lastIndexOf(segment);
  if (i < 0 || i + 1 >= seg.length) return null;
  final id = seg[i + 1];
  return _uuid.hasMatch(id) ? id : null;
}
