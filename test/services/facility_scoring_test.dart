import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/facility_repository.dart';

Facility fac(String name, {String category = 'pet_sales'}) => Facility(
  id: 'f1',
  category: category,
  name: name,
  address: null,
  phone: null,
  isOpen: true,
  lat: 0,
  lng: 0,
  distanceM: 0,
);

void main() {
  group('evaluatePetSales — 분양업 상호 신뢰도 점수화', () {
    test('pet_sales 가 아니면 평가하지 않는다(null)', () {
      expect(evaluatePetSales(fac('분양천국', category: 'grooming')), isNull);
    });

    test('가점 단어(분양)만 있으면 likely + 양수 점수', () {
      final s = evaluatePetSales(fac('행복 분양샵'))!;
      expect(s.level, PetSalesTrust.likely);
      expect(s.score, 1);
      expect(s.positives, ['분양']);
      expect(s.negatives, isEmpty);
    });

    test('감점 단어(용품)만 있으면 caution + 음수 점수', () {
      final s = evaluatePetSales(fac('멍멍 용품샵'))!;
      expect(s.level, PetSalesTrust.caution);
      expect(s.score, -1);
      expect(s.negatives, ['용품']);
    });

    test('감점 단어는 영문 대소문자 무시 매칭(Company)', () {
      final s = evaluatePetSales(fac('PET Company'))!;
      expect(s.level, PetSalesTrust.caution);
      expect(s.negatives, ['company']);
    });

    test('키워드가 전혀 없으면 unclear(0점)', () {
      final s = evaluatePetSales(fac('동물사랑'))!;
      expect(s.level, PetSalesTrust.unclear);
      expect(s.score, 0);
    });

    test('가점·감점 동수면 unclear', () {
      final s = evaluatePetSales(fac('분양용품'))!;
      expect(s.score, 0);
      expect(s.level, PetSalesTrust.unclear);
    });

    test('화이트리스트 브랜드는 (주) 등 감점 단어가 있어도 무조건 신뢰', () {
      final s = evaluatePetSales(fac('(주)도그마루'))!;
      expect(s.level, PetSalesTrust.likely);
      expect(s.negatives, isEmpty, reason: '브랜드면 감점을 무시한다');
      expect(s.positives, contains('도그마루'));
    });

    test('화이트리스트 + 가점 단어는 근거에 함께 표시된다', () {
      final s = evaluatePetSales(fac('(주)도그마루 분양센터'))!;
      expect(s.positives, containsAll(['도그마루', '분양']));
      expect(s.score, 2);
    });
  });

  group('isLowTrustHidden — 저신뢰 숨김 판정(점수 ≤ -2)', () {
    test('감점 2개 이상 누적이면 숨긴다', () {
      expect(isLowTrustHidden(fac('(주)펫용품컴퍼니')), isTrue);
    });

    test('감점 1개(-1)는 숨기지 않는다(주의 표시만)', () {
      expect(isLowTrustHidden(fac('멍멍 용품샵')), isFalse);
    });

    test('pet_sales 가 아니면 절대 숨기지 않는다', () {
      expect(isLowTrustHidden(fac('(주)펫용품컴퍼니', category: 'pet_cafe')), isFalse);
    });
  });
}
