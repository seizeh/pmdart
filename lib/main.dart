/// 진입점 — 하는 일은 부트스트랩을 부르는 것뿐이다.
///
/// 초기화 순서는 `app/bootstrap.dart`, 푸시 탭 라우팅은 `app/push_routing.dart`,
/// 앱 위젯은 `app/pawmate_app.dart` 에 있다. 종전에는 셋이 이 파일에 함께 있었다.
library;

import 'app/bootstrap.dart';

Future<void> main() => AppBootstrap.run();
