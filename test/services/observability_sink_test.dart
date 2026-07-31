import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/error_reporter.dart';
import 'package:pawmate/services/observability.dart';

/// 어느 빌드가 오류를 서버로 보내는지 고정한다.
///
/// 한 번 어긋난 적이 있다 — 디버그 빌드가 운영 `app.client_errors` 로 바로 보내는
/// 바람에 개발 중 위젯 어서션 수십 건이 실사용자 오류 사이에 섞였다. 조건이
/// 세 갈래라 눈으로는 다시 틀리기 쉬워 테스트로 못 박는다.
void main() {
  group('Observability.resolveSink', () {
    test('릴리스는 항상 서버로 보낸다', () {
      expect(
        Observability.resolveSink(debugMode: false, reportInDebug: false),
        isA<SupabaseErrorSink>(),
      );
    });

    test('릴리스는 디버그 플래그에 영향받지 않는다', () {
      expect(
        Observability.resolveSink(debugMode: false, reportInDebug: true),
        isA<SupabaseErrorSink>(),
      );
    });

    test('디버그 기본값은 콘솔만 — 운영 테이블로 안 보낸다', () {
      final sink = Observability.resolveSink(
        debugMode: true,
        reportInDebug: false,
      );
      expect(sink, isA<DebugErrorSink>());
      expect(sink, isNot(isA<SupabaseErrorSink>()));
      expect(sink, isNot(isA<FanOutErrorSink>()));
    });

    test('디버그 + 플래그를 켜면 콘솔과 서버 양쪽', () {
      final sink = Observability.resolveSink(
        debugMode: true,
        reportInDebug: true,
      );
      expect(sink, isA<FanOutErrorSink>());
    });
  });
}
