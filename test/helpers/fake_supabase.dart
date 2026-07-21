/// 테스트용 Supabase 초기화 — 실제 네트워크 대신 등록된 라우트로 응답한다.
///
/// 서비스 레이어가 `Supabase.instance.client` 싱글턴을 직접 참조하므로,
/// http 레이어(MockClient)에서 요청을 가로채면 프로덕션 코드 수정 없이
/// 리포지토리 메서드를 단위 테스트할 수 있다. 각 테스트 파일은 독립
/// 프로세스라 파일당 한 번 [init] 하면 된다.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeSupabase {
  FakeSupabase._();

  /// 수행된 모든 요청 — 경로/쿼리/바디 검증용.
  static final List<http.Request> requests = [];

  static final Map<String, Object? Function(http.Request req)> _routes = {};

  static Future<void> init() async {
    // supabase_flutter 가 PKCE 비동기 저장소로 SharedPreferences 를 무조건
    // 초기화하므로 테스트에선 채널을 목으로 대체해야 한다.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fake.supabase.test',
      publishableKey: 'sb_publishable_fake',
      httpClient: MockClient(_handle),
      authOptions: FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  }

  /// [pathContains] 가 요청 경로에 부분일치하면 [respond] 의 반환값을
  /// JSON 으로 응답한다. 나중에 등록한 라우트가 우선.
  /// [respond] 가 `http.Response` 를 반환하면 상태코드·헤더 그대로 응답하고
  /// (에러 응답 테스트용), 예외를 던지면 네트워크 오류를 흉내낸다.
  static void on(
    String pathContains,
    Object? Function(http.Request req) respond,
  ) {
    _routes[pathContains] = respond;
  }

  /// 상태코드를 지정한 JSON 에러 응답 (FunctionException/PostgrestException 유발).
  static http.Response error(int status, Object? body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  static void reset() {
    requests.clear();
    _routes.clear();
  }

  static Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    for (final e in _routes.entries.toList().reversed) {
      if (req.url.path.contains(e.key)) {
        final result = e.value(req);
        if (result is http.Response) {
          return http.Response(
            result.body,
            result.statusCode,
            headers: {'content-type': 'application/json', ...result.headers},
            request: req,
          );
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      }
    }
    return http.Response(
      '[]',
      200,
      headers: {'content-type': 'application/json'},
      request: req,
    );
  }
}
