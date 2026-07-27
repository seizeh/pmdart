import 'package:web/web.dart' as web;

/// `<meta name="pm-post" content="<uuid>">` 의 값. 없으면 null.
String? injectedPostId() {
  final el = web.document.querySelector('meta[name="pm-post"]');
  final v = el?.getAttribute('content');
  return (v == null || v.isEmpty) ? null : v;
}
