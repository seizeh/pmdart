import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/utils/phone_format.dart';

void main() {
  test('앞 0 복원 + 지역번호 하이픈', () {
    expect(formatKrPhone('313737588'), '031-373-7588'); // 뉴엘 사례
    expect(formatKrPhone('312927504'), '031-292-7504');
    expect(formatKrPhone('3180073103'), '031-8007-3103'); // 11자리(0포함)
  });

  test('서울 02', () {
    expect(formatKrPhone('24468175'), '02-446-8175'); // 8자리
    expect(formatKrPhone('222377582'), '02-2237-7582'); // 9자리
  });

  test('070 / 010', () {
    expect(formatKrPhone('7086600904'), '070-8660-0904');
    expect(formatKrPhone('01012345678'), '010-1234-5678');
  });

  test('이미 하이픈이 있어도 동일 결과(정규화 후 재포맷)', () {
    expect(formatKrPhone('031-373-7588'), '031-373-7588');
    expect(formatKrPhone('031 373 7588'), '031-373-7588');
  });

  test('빈/널/대표번호', () {
    expect(formatKrPhone(null), '');
    expect(formatKrPhone(''), '');
    expect(formatKrPhone('15881234'), '1588-1234');
  });
}
