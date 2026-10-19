import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../env.dart';
import 'error_reporter.dart';

/// 행안부 도로명주소(juso.go.kr) 검색 (0025 §4.2).
/// 자유 텍스트 대신 검색 결과에서 선택 → 도로명·지번·행정코드를 표준 형태로 확보한다
/// (지번은 facilities 대조, 행정코드는 시군구 일치 점수에 쓰인다).
///
/// 키는 juso.go.kr 개발자센터에서 발급(무료) — 미설정 시 검색이 비활성화되고
/// 업체등록 화면이 수동 입력으로 폴백한다(주소 점수만 빠지고 신청은 가능).
class JusoService {
  JusoService._(this._key);
  static final JusoService instance = JusoService._(Env.jusoApiKey);

  /// 테스트 전용 — 빌드 정의(--dart-define) 없이 키를 꽂는다.
  @visibleForTesting
  JusoService.withKey(String key) : _key = key;

  /// 발급받은 confmKey — 클라이언트 키(네이버 지도 clientId 와 같은 취급).
  /// --dart-define=JUSO_API_KEY=... 로 주입한다(lib/env.dart).
  final String _key;

  /// 실패를 화면에 알릴 때의 문구(검색어 문제가 아닌 실패 전부).
  static const failMessage = '주소 검색에 실패했어요. 잠시 후 다시 시도해주세요';

  /// 검색어 자체의 문제를 뜻하는 juso 오류 코드 — 응답의 errorMessage 가 이미
  /// 사용자용 문구라 그대로 보여 준다(예: E0013 "SQL 예약어 또는 특수문자 … 검색이
  /// 불가능 합니다"). 그 밖의 코드(E0001 승인되지 않은 키, E0014 개발키 만료,
  /// -999 시스템 오류)는 설정·서버 문제라 오류로 보고한다.
  static const _inputErrorCodes = {
    'E0005', // 검색어 미입력
    'E0006', // 주소를 상세히 입력
    'E0008', // 두 글자 이상
    'E0009', // 문자와 숫자를 같이
    'E0010', // 검색어가 너무 길다
    'E0011', // 너무 긴 숫자
    'E0012', // 특수문자+숫자만
    'E0013', // SQL 예약어·특수문자
    'E0015', // 검색 범위 초과
  };

  static bool _missingKeyReported = false;

  /// 검색을 쓸 수 있는가. 키 없이 빌드됐으면 false — 업체 등록이 수동 입력으로
  /// 바뀐다. 그 사실이 조용히 지나가지 않도록 프로세스당 한 번 오류로 남긴다
  /// (릴리스·웹 빌드에서 키가 빠져 검색 버튼이 통째로 사라졌던 적이 있다).
  bool get enabled {
    if (_key.isNotEmpty) return true;
    if (!_missingKeyReported) {
      _missingKeyReported = true;
      ErrorReporter.report(
        StateError('JUSO_API_KEY 없이 빌드됨 — 주소 검색이 수동 입력으로 바뀐다'),
        where: 'juso.keyMissing',
      );
    }
    return false;
  }

  /// 키워드 검색 (예: 도로명, 건물명, 지번). 결과가 없으면 빈 목록이고,
  /// 실패하면 [JusoSearchResult.message] 에 화면에 띄울 문구가 담긴다.
  Future<JusoSearchResult> search(String keyword, {int page = 1}) async {
    final q = keyword.trim();
    if (!enabled || q.length < 2) return const JusoSearchResult([]);
    try {
      final uri =
          Uri.parse(
            'https://business.juso.go.kr/addrlink/addrLinkApi.do',
          ).replace(
            queryParameters: {
              'confmKey': _key,
              'currentPage': '$page',
              'countPerPage': '20',
              'keyword': q,
              'resultType': 'json',
            },
          );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        ErrorReporter.report(
          StateError('juso HTTP ${res.statusCode}'),
          where: 'juso.search',
          extra: {'status': res.statusCode},
        );
        return const JusoSearchResult([], message: failMessage);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as Map<String, dynamic>?;
      final common = results?['common'] as Map<String, dynamic>?;
      final code = common?['errorCode'] as String?;
      if (code != '0') {
        final apiMessage = (common?['errorMessage'] as String?)?.trim() ?? '';
        if (_inputErrorCodes.contains(code) && apiMessage.isNotEmpty) {
          return JusoSearchResult(const [], message: apiMessage);
        }
        ErrorReporter.report(
          StateError('juso $code: $apiMessage'),
          where: 'juso.search',
          extra: {'errorCode': code},
        );
        return const JusoSearchResult([], message: failMessage);
      }
      final list = (results?['juso'] as List?) ?? const [];
      return JusoSearchResult(
        [
          for (final j in list.cast<Map<String, dynamic>>())
            JusoAddress(
              roadAddr: (j['roadAddr'] as String?) ?? '',
              jibunAddr: (j['jibunAddr'] as String?) ?? '',
              admCd: (j['admCd'] as String?) ?? '',
              zipNo: (j['zipNo'] as String?) ?? '',
            ),
        ].where((a) => a.roadAddr.isNotEmpty).toList(),
      );
    } on TimeoutException catch (e, st) {
      ErrorReporter.userFacing(e, where: 'juso.search', stackTrace: st);
      return const JusoSearchResult([], message: failMessage);
    } on http.ClientException catch (e, st) {
      // 네트워크 끊김 등 — 서버·코드 문제가 아니라 안내만 한다.
      ErrorReporter.userFacing(e, where: 'juso.search', stackTrace: st);
      return const JusoSearchResult([], message: failMessage);
    } catch (e, st) {
      // 응답 형식이 바뀌었거나(파싱 실패) 예상 못 한 오류 — 보고한다.
      ErrorReporter.report(e, where: 'juso.search', stackTrace: st);
      return const JusoSearchResult([], message: failMessage);
    }
  }

  /// 테스트 전용 — 키 누락 보고를 다시 할 수 있게 되돌린다.
  @visibleForTesting
  static void resetForTest() => _missingKeyReported = false;
}

/// 주소 검색 결과. [message] 가 있으면 실패(또는 검색어 문제)로, 화면은 결과 목록
/// 대신 이 문구를 보여 준다. 결과가 비었어도 [message] 가 null 이면 정상이다.
class JusoSearchResult {
  final List<JusoAddress> addresses;
  final String? message;
  const JusoSearchResult(this.addresses, {this.message});
}

class JusoAddress {
  final String roadAddr; // 도로명 전체 주소
  final String jibunAddr; // 지번 전체 주소 (facilities.address 대조용)
  final String admCd; // 행정구역코드 10자리 (앞 5자리 = 시군구)
  final String zipNo;
  const JusoAddress({
    required this.roadAddr,
    required this.jibunAddr,
    required this.admCd,
    required this.zipNo,
  });
}
