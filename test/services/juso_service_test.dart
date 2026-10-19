import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawmate/services/error_reporter.dart';
import 'package:pawmate/services/juso_service.dart';

/// 주소 검색(행안부 juso)의 실패 구분 회귀 가드.
///
/// 종전에는 키 누락·키 오류·네트워크 실패·검색어 문제가 전부 빈 목록으로 뭉개져
/// "검색 결과가 없어요" 하나로 보였고 어디에도 기록되지 않았다. 릴리스·웹 빌드에
/// 키가 빠져 주소 검색이 통째로 사라졌는데도 아무도 알아채지 못했다.
class _Sink implements ErrorSink {
  final records = <ErrorRecord>[];
  @override
  void add(ErrorRecord record) => records.add(record);
  @override
  void breadcrumb(String m, {String? category, Map<String, Object?>? data}) {}
}

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json;charset=UTF-8'},
    );

Map<String, Object?> _common(String code, String message, {int total = 0}) => {
  'results': {
    'common': {
      'errorCode': code,
      'errorMessage': message,
      'totalCount': '$total',
    },
    'juso': code == '0' ? <Object?>[] : null,
  },
};

void main() {
  late _Sink sink;
  final juso = JusoService.withKey('test-key');

  setUp(() {
    ErrorReporter.resetForTest();
    JusoService.resetForTest();
    sink = _Sink();
    ErrorReporter.sink = sink;
  });

  tearDown(ErrorReporter.resetForTest);

  Future<JusoSearchResult> searchWith(
    FutureOr<http.Response> Function(http.Request) handler,
    String keyword,
  ) => http.runWithClient(
    () => juso.search(keyword),
    () => MockClient((req) async => handler(req)),
  );

  test('정상 응답은 주소 목록, 안내 없음, 기록 없음', () async {
    late Uri sent;
    final r = await searchWith((req) {
      sent = req.url;
      return _json({
        'results': {
          'common': {'errorCode': '0', 'errorMessage': '정상', 'totalCount': '1'},
          'juso': [
            {
              'roadAddr': '경기도 화성시 동탄대로 537',
              'jibunAddr': '경기도 화성시 오산동 1023',
              'admCd': '4159012000',
              'zipNo': '18471',
            },
          ],
        },
      });
    }, '  동탄대로 537 ');

    expect(sent.queryParameters['keyword'], '동탄대로 537');
    expect(sent.queryParameters['confmKey'], 'test-key');
    expect(r.message, isNull);
    expect(r.addresses.single.jibunAddr, '경기도 화성시 오산동 1023');
    expect(sink.records, isEmpty);
  });

  test('결과가 없어도 정상이다 — 안내 문구 없이 빈 목록', () async {
    final r = await searchWith((_) => _json(_common('0', '정상')), '없는주소');
    expect(r.addresses, isEmpty);
    expect(r.message, isNull);
    expect(sink.records, isEmpty);
  });

  test('검색어 문제(E0013)는 API 문구를 그대로 보여 주고 오류로 보고하지 않는다', () async {
    const apiMessage = 'SQL 예약어 또는 특수문자( %,=,>,<,[,] )는 검색이 불가능 합니다.';
    final r = await searchWith(
      (_) => _json(_common('E0013', apiMessage)),
      'select',
    );
    expect(r.message, apiMessage);
    expect(sink.records, isEmpty);
  });

  test('키 문제(E0001)는 실패 안내 + 보고', () async {
    final r = await searchWith(
      (_) => _json(_common('E0001', '승인되지 않은 KEY 입니다.')),
      '동탄대로',
    );
    expect(r.message, JusoService.failMessage);
    final rec = sink.records.single;
    expect(rec.tier, ErrorTier.reported);
    expect(rec.where, 'juso.search');
    expect(rec.extra?['errorCode'], 'E0001');
  });

  test('HTTP 오류는 실패 안내 + 보고', () async {
    final r = await searchWith((_) => http.Response('busy', 503), '동탄대로');
    expect(r.message, JusoService.failMessage);
    expect(sink.records.single.tier, ErrorTier.reported);
    expect(sink.records.single.extra?['status'], 503);
  });

  test('네트워크 실패는 실패 안내 + 사용자 등급(서버·코드 문제가 아니다)', () async {
    final r = await searchWith(
      (_) => throw http.ClientException('connection reset'),
      '동탄대로',
    );
    expect(r.message, JusoService.failMessage);
    expect(sink.records.single.tier, ErrorTier.userFacing);
  });

  test('한 글자 검색은 서버에 묻지 않는다', () async {
    var called = false;
    final r = await searchWith((_) {
      called = true;
      return _json(_common('0', '정상'));
    }, '동');
    expect(called, isFalse);
    expect(r.addresses, isEmpty);
    expect(r.message, isNull);
  });

  test('키 없이 빌드되면 비활성 + 한 번만 보고한다', () async {
    final noKey = JusoService.withKey('');
    expect(noKey.enabled, isFalse);
    expect(noKey.enabled, isFalse);
    final r = await noKey.search('동탄대로');
    expect(r.addresses, isEmpty);
    expect(sink.records, hasLength(1));
    expect(sink.records.single.where, 'juso.keyMissing');
    expect(sink.records.single.tier, ErrorTier.reported);
  });
}
