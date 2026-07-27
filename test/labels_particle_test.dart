import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/utils/labels.dart';

void main() {
  group('withTopicParticle', () {
    test('받침 없으면 는', () {
      expect(withTopicParticle('지도'), '지도는');
      expect(withTopicParticle('커뮤니티'), '커뮤니티는');
    });

    test('받침 있으면 은', () {
      expect(withTopicParticle('채팅'), '채팅은');
      expect(withTopicParticle('알림'), '알림은');
    });

    test('한글이 아니면 는으로 둔다(판별 불가)', () {
      expect(withTopicParticle('PawMate'), 'PawMate는');
      expect(withTopicParticle('123'), '123는');
    });

    test('빈 문자열은 그대로', () => expect(withTopicParticle(''), ''));
  });
}
