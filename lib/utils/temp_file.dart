/// 임시 파일 삭제 — `dart:io` 를 앱 코드에서 직접 쓰지 않기 위한 얇은 파사드.
/// 웹에는 파일 시스템이 없으므로 no-op(브라우저가 blob 을 알아서 회수한다).
library;

export 'temp_file_io.dart' if (dart.library.js_interop) 'temp_file_web.dart';
