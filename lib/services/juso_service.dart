import 'dart:convert';

import 'package:http/http.dart' as http;

/// 행안부 도로명주소(juso.go.kr) 검색 (0025 §4.2).
/// 자유 텍스트 대신 검색 결과에서 선택 → 도로명·지번·행정코드를 표준 형태로 확보한다
/// (지번은 facilities 대조, 행정코드는 시군구 일치 점수에 쓰인다).
///
/// 키는 juso.go.kr 개발자센터에서 발급(무료) — 미설정 시 검색이 비활성화되고
/// 업체등록 화면이 수동 입력으로 폴백한다(주소 점수만 빠지고 신청은 가능).
class JusoService {
  JusoService._();
  static final JusoService instance = JusoService._();

  /// 발급받은 confmKey. --dart-define=JUSO_API_KEY=... 로 주입(기본 빈값 = 비활성).
  static const _key = String.fromEnvironment('JUSO_API_KEY');

  bool get enabled => _key.isNotEmpty;

  /// 키워드 검색 (예: 도로명, 건물명, 지번). 실패/무결과 시 빈 목록.
  Future<List<JusoAddress>> search(String keyword, {int page = 1}) async {
    if (!enabled || keyword.trim().length < 2) return const [];
    try {
      final uri = Uri.parse('https://business.juso.go.kr/addrlink/addrLinkApi.do')
          .replace(
            queryParameters: {
              'confmKey': _key,
              'currentPage': '$page',
              'countPerPage': '20',
              'keyword': keyword.trim(),
              'resultType': 'json',
            },
          );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as Map<String, dynamic>?;
      if (results?['common']?['errorCode'] != '0') return const [];
      final list = (results?['juso'] as List?) ?? const [];
      return [
        for (final j in list.cast<Map<String, dynamic>>())
          JusoAddress(
            roadAddr: (j['roadAddr'] as String?) ?? '',
            jibunAddr: (j['jibunAddr'] as String?) ?? '',
            admCd: (j['admCd'] as String?) ?? '',
            zipNo: (j['zipNo'] as String?) ?? '',
          ),
      ].where((a) => a.roadAddr.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }
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
