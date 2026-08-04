import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/realtime_service.dart';

/// 구독 상태 기계는 웹소켓이 필요해 단위 테스트가 어렵다. 백오프 규칙만 순수
/// 계산으로 빼 두었으므로 그건 잰다 — 규칙이 바뀌면 여기가 먼저 빨간불이 된다.
///
/// 특히 **상한**이 중요하다. 상한이 없으면 오래 끊긴 뒤 재시도 간격이 수십 분으로
/// 벌어지고, 그러면 사용자는 앱을 껐다 켜야 한다 — 이 수정이 없애려던 상태 그 자체다.
void main() {
  group('realtimeRetryDelay — 재구독 백오프', () {
    test('첫 실패는 2초 뒤 재시도한다(즉시 재시도로 서버를 때리지 않는다)', () {
      expect(realtimeRetryDelay(1), const Duration(seconds: 2));
    });

    test('실패가 이어지면 간격이 배로 늘어난다', () {
      expect(realtimeRetryDelay(2), const Duration(seconds: 4));
      expect(realtimeRetryDelay(3), const Duration(seconds: 8));
      expect(realtimeRetryDelay(4), const Duration(seconds: 16));
      expect(realtimeRetryDelay(5), const Duration(seconds: 32));
    });

    test('60초에서 멈춘다 — 복구 시도가 1분 안에는 반드시 일어나야 한다', () {
      expect(realtimeRetryDelay(6), const Duration(seconds: 60));
      expect(realtimeRetryDelay(7), const Duration(seconds: 60));
      expect(realtimeRetryDelay(50), const Duration(seconds: 60));
      expect(realtimeRetryDelay(100000), const Duration(seconds: 60));
    });

    test('간격은 단조 증가하고 절대 0이 되지 않는다', () {
      var prev = Duration.zero;
      for (var i = 1; i <= 20; i++) {
        final d = realtimeRetryDelay(i);
        expect(d.inSeconds, greaterThan(0), reason: '$i회차가 즉시 재시도가 되면 폭주한다');
        expect(
          d.inSeconds,
          greaterThanOrEqualTo(prev.inSeconds),
          reason: '$i회차',
        );
        prev = d;
      }
    });

    test('비정상 입력(0·음수)도 즉시 재시도가 되지 않는다', () {
      expect(realtimeRetryDelay(0), const Duration(seconds: 2));
      expect(realtimeRetryDelay(-1), const Duration(seconds: 2));
    });
  });
}
