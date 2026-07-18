/// 한국 전화번호 표시 포맷 — 하이픈 삽입 + 빠진 앞 0 복원.
///
/// 공공데이터(LOCALDATA) 전화는 하이픈이 없고 지역번호 앞 0 이 손실돼 있다
/// (예: '313737588' → 실제 031-373-7588, '24468175' → 02-446-8175).
/// 숫자만 남긴 뒤 앞 0 을 복원하고 국번 규칙대로 하이픈을 넣는다.
///
/// 업체가 정보 수정에서 하이픈을 넣든 안 넣든 저장은 숫자만(서버 정규화)이고,
/// 표시는 항상 이 함수를 거치므로 일관된 형식으로 보인다.
String formatKrPhone(String? raw) {
  if (raw == null) return '';
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return raw;

  // 앞 0 복원 — 2~9 로 시작하면 지역번호/휴대폰의 0 이 빠진 것(1 은 대표번호).
  if (!d.startsWith('0') && !d.startsWith('1')) d = '0$d';

  // 서울(02) — 지역번호가 2자리.
  if (d.startsWith('02')) {
    final rest = d.substring(2);
    if (rest.length == 7) {
      return '02-${rest.substring(0, 3)}-${rest.substring(3)}';
    }
    if (rest.length == 8) {
      return '02-${rest.substring(0, 4)}-${rest.substring(4)}';
    }
    return d;
  }

  // 3자리 국번(0XX·070·010) — 10자리 3-3-4, 11자리 3-4-4.
  if (d.length == 10) {
    return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
  }
  if (d.length == 11) {
    return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}';
  }

  // 대표번호(1588-XXXX 등) 8자리.
  if (d.startsWith('1') && d.length == 8) {
    return '${d.substring(0, 4)}-${d.substring(4)}';
  }

  return d; // 규칙 밖은 숫자 그대로(하이픈 없이).
}
