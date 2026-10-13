import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/profile_repository.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/utils/vaccination_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'pet_owner',
);

/// 내 반려동물 목록의 **종(species_kind)** 회귀 가드.
///
/// 실제 결함: 내 정보 탭의 펫 목록 조회가 species_kind 를 싣지 않았다. 펫 상세의
/// "접종 일정" 은 그 Pet 을 그대로 넘기므로 종이 null 이 되고, 표준 일정 계산은
/// null 을 강아지로 본다 — 고양이에게 DHPPL·켄넬코프 일정이 저장됐다.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await FakeSupabase.init();
  });

  setUp(() async {
    FakeSupabase.reset();
    await SessionManager.instance.setSession(
      jwtWithExp(nowSec() + 3600),
      _me,
      refresh: 'r1',
    );
  });

  test('내 반려동물은 종을 싣고 온다 — 고양이는 고양이 일정표를 고른다', () async {
    FakeSupabase.on(
      'public_profiles',
      (_) => [
        {'id': 'u1', 'nickname': '나', 'user_type': 'pet_owner'},
      ],
    );
    FakeSupabase.on(
      'users',
      (_) => [
        {'active_mode': 'personal'},
      ],
    );
    FakeSupabase.on('pet_guardians', (req) {
      final select = req.url.queryParameters['select'] ?? '';
      if (!select.contains('pets(')) {
        return [
          {'pet_id': 'pet1'},
        ];
      }
      // 서버는 요청한 컬럼만 돌려준다 — select 에 없으면 값도 없다.
      return [
        {
          'role': 'owner',
          'pets': {
            'id': 'pet1',
            'name': '나비',
            'species': '코리안숏헤어',
            if (select.contains('species_kind')) 'species_kind': 'cat',
            'gender': 'female',
            'birth_date': '2026-08-01',
            'bio': null,
            'image_url': null,
            'pet_status': 'active',
            'primary_guardian_id': 'u1',
            'identity_verified': false,
            'pet_match_count': 0,
          },
        },
      ];
    });

    final data = await ProfileRepository.instance.fetchProfile();

    final pet = data.pets.single;
    expect(pet.speciesKind, 'cat');
    final labels = standardVaccinationSchedule(
      birthDate: pet.birthDate!,
      speciesKind: pet.speciesKind,
    ).map((v) => v.label);
    expect(labels, contains('종합백신(FVRCP) 1차'));
    expect(labels.where((l) => l.contains('DHPPL')), isEmpty);
  });
}
