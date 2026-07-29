import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/error_reporter.dart';

/// 등급별로 무엇이 sink 로 흘러갔는지만 본다.
class _RecordingSink implements ErrorSink {
  final records = <ErrorRecord>[];
  final crumbs = <String>[];

  @override
  void add(ErrorRecord record) => records.add(record);

  @override
  void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  }) => crumbs.add('${category ?? 'app'}:$message');
}

void main() {
  late _RecordingSink sink;

  setUp(() {
    ErrorReporter.resetForTest();
    sink = _RecordingSink();
    ErrorReporter.sink = sink;
  });

  tearDown(ErrorReporter.resetForTest);

  test('등급이 그대로 기록된다', () {
    ErrorReporter.ignored('e1', where: 'a.b', why: '무해함');
    ErrorReporter.userFacing('e2', where: 'c.d');
    ErrorReporter.report('e3', where: 'e.f', stackTrace: StackTrace.current);

    expect(sink.records.map((r) => r.tier), [
      ErrorTier.ignored,
      ErrorTier.userFacing,
      ErrorTier.reported,
    ]);
    expect(sink.records.first.why, '무해함');
    expect(sink.records.last.stackTrace, isNotNull);
  });

  test('등급과 무관하게 recent 에 남는다 — 원격 전송이 꺼져 있어도 진단은 된다', () {
    ErrorReporter.sink = const SilentErrorSink();

    ErrorReporter.ignored('e', where: 'a.b', why: 'x');
    ErrorReporter.report('e', where: 'c.d');

    expect(ErrorReporter.recent, hasLength(2));
    expect(ErrorReporter.recent.last.where, 'c.d');
  });

  test('recent 는 상한을 넘으면 오래된 것부터 버린다', () {
    for (var i = 0; i < 60; i++) {
      ErrorReporter.ignored('e$i', where: 'w$i', why: 'x');
    }

    expect(ErrorReporter.recent, hasLength(50));
    expect(ErrorReporter.recent.first.where, 'w10'); // 앞 10건은 밀려났다
    expect(ErrorReporter.recent.last.where, 'w59');
  });

  test('브레드크럼은 sink 로만 가고 recent 를 채우지 않는다', () {
    ErrorReporter.breadcrumb('열림', category: 'nav');

    expect(sink.crumbs, ['nav:열림']);
    expect(ErrorReporter.recent, isEmpty);
  });

  test('toString 에 등급·지점·무시 근거가 들어간다', () {
    ErrorReporter.ignored('boom', where: 'a.b', why: '햅틱 미지원');

    final s = sink.records.single.toString();
    expect(s, contains('[ignored]'));
    expect(s, contains('a.b'));
    expect(s, contains('햅틱 미지원'));
  });

  test('FanOut 은 모든 sink 에 같은 기록을 넘긴다', () {
    final a = _RecordingSink();
    final b = _RecordingSink();
    ErrorReporter.sink = FanOutErrorSink([a, b]);

    ErrorReporter.report('e', where: 'x.y');
    ErrorReporter.breadcrumb('m');

    expect(a.records, hasLength(1));
    expect(b.records, hasLength(1));
    expect(a.crumbs, hasLength(1));
    expect(b.crumbs, hasLength(1));
  });
}
