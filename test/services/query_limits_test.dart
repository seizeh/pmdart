import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/error_reporter.dart';
import 'package:pawmate/services/query_limits.dart';

/// 절단 감지는 **안 터질 때 조용해야** 쓸모가 있다. 평상시에 보고가 새면 진짜
/// 절단이 그 안에 묻히고, 그건 이 장치가 없애려는 상태(아무도 모름)와 같아진다.
///
/// ErrorReporter 는 초기화 API 가 없고 링 버퍼(50)만 있으므로, 테스트마다 고유한
/// `where` 로 남긴 기록만 세어 서로 간섭하지 않게 한다.
void main() {
  int reportedAt(String where) => ErrorReporter.recent
      .where((r) => r.where == where && r.tier == ErrorTier.reported)
      .length;

  group('guardTruncation — 조용한 절단 감지', () {
    test('상한 미만이면 아무것도 보고하지 않는다', () {
      final rows = List.generate(kServerMaxRows - 1, (i) => i);
      expect(guardTruncation(rows, where: 'test.under'), rows);
      expect(reportedAt('test.under'), 0, reason: '평상시 조용해야 진짜 절단이 눈에 띈다');
    });

    test('빈 목록도 조용하다', () {
      expect(guardTruncation(<int>[], where: 'test.empty'), isEmpty);
      expect(reportedAt('test.empty'), 0);
    });

    test('서버 상한(1000)에 정확히 닿으면 보고한다', () {
      guardTruncation(
        List.generate(kServerMaxRows, (i) => i),
        where: 'test.at_cap',
      );
      expect(reportedAt('test.at_cap'), 1);
    });

    test('행은 그대로 돌려준다 — 감지가 데이터를 바꾸지 않는다', () {
      final rows = List.generate(kServerMaxRows, (i) => i);
      final out = guardTruncation(rows, where: 'test.passthrough');
      expect(identical(out, rows), isTrue);
      expect(out.length, kServerMaxRows);
    });

    test('명시적 상한을 주면 그 값을 기준으로 본다', () {
      final rows = List.generate(50, (i) => i);
      guardTruncation(rows, where: 'test.hit_50', limit: 50);
      expect(reportedAt('test.hit_50'), 1, reason: '50개 요청에 50개가 오면 잘렸을 수 있다');

      guardTruncation(rows, where: 'test.under_100', limit: 100);
      expect(reportedAt('test.under_100'), 0, reason: '100개 요청에 50개면 전부 온 것');
    });

    test('보고에 실제 행 수와 상한이 함께 담긴다(어느 목록이 얼마나인지)', () {
      guardTruncation(
        List.generate(kServerMaxRows, (i) => i),
        where: 'test.extra',
      );
      final rec = ErrorReporter.recent.lastWhere(
        (r) => r.where == 'test.extra',
      );
      expect(rec.extra?['rows'], kServerMaxRows);
      expect(rec.extra?['cap'], kServerMaxRows);
    });
  });
}
