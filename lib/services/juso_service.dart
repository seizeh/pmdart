import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_reporter.dart';

/// 행안부 도로명주소(juso.go.kr) 검색 (0025 §4.2).
/// 자유 텍스트 대신 검색 결과에서 선택 → 도로명·지번·행정코드를 표준 형태로 확보한다
/// (지번은 facilities 대조, 행정코드는 시군구 일치 점수에 쓰인다).
///
/// 승인키는 서버에만 있다 — Edge Function `juso-search` 가 대신 부른다. 종전에는 앱이
/// 키를 들고 직접 불렀는데, 키가 번들에 실리면 공개 저장소·웹 JS 에서 꺼내 쓸 수 있어
/// 소스 기본값을 지웠고, 그 뒤로는 빌드에 키를 넣지 않으면 검색이 조용히 사라졌다.
class JusoService {
  JusoService._();
  static final JusoService instance = JusoService._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 실패를 화면에 알릴 때의 문구(검색어 문제·호출 제한이 아닌 실패 전부).
  static const failMessage = '주소 검색에 실패했어요. 잠시 후 다시 시도해주세요';

  /// 계정당 호출 제한(서버 60회/시간)에 걸렸을 때.
  static const rateLimitedMessage = '검색을 너무 자주 했어요. 잠시 후 다시 시도해주세요';

  /// 키워드 검색 (예: 도로명, 건물명, 지번). 결과가 없으면 빈 목록이고,
  /// 실패하면 [JusoSearchResult.message] 에 화면에 띄울 문구가 담긴다.
  Future<JusoSearchResult> search(String keyword, {int page = 1}) async {
    final q = keyword.trim();
    if (q.length < 2) return const JusoSearchResult([]);
    try {
      final res = await _c.functions.invoke(
        'juso-search',
        body: {'keyword': q, 'page': page},
      );
      final data = (res.data as Map?) ?? const {};
      final list = (data['results'] as List?) ?? const [];
      return JusoSearchResult(
        [
          for (final j in list.cast<Map<String, dynamic>>())
            JusoAddress(
              roadAddr: (j['road_addr'] as String?) ?? '',
              jibunAddr: (j['jibun_addr'] as String?) ?? '',
              admCd: (j['adm_cd'] as String?) ?? '',
              zipNo: (j['zip_no'] as String?) ?? '',
            ),
        ].where((a) => a.roadAddr.isNotEmpty).toList(),
      );
    } on FunctionException catch (e) {
      final details = e.details is Map ? e.details as Map : const {};
      final message = details['message'];
      // 검색어 문제(특수문자·너무 짧음 등) — 서버가 넘긴 juso 문구가 이미 사용자용이다.
      if (e.status == 422 && message is String && message.isNotEmpty) {
        return JusoSearchResult(const [], message: message);
      }
      if (e.status == 429) {
        ErrorReporter.userFacing(e, where: 'juso.search');
        return const JusoSearchResult([], message: rateLimitedMessage);
      }
      // 키 오류는 서버가 관리자에게 알린다. 여기서는 어떤 응답이었는지만 남긴다.
      ErrorReporter.report(
        e,
        where: 'juso.search',
        extra: {'status': e.status, 'error': details['error']},
      );
      return const JusoSearchResult([], message: failMessage);
    } catch (e, st) {
      // 네트워크 끊김·시간 초과 등 — 서버·코드 문제가 아니라 안내만 한다.
      ErrorReporter.userFacing(e, where: 'juso.search', stackTrace: st);
      return const JusoSearchResult([], message: failMessage);
    }
  }
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
