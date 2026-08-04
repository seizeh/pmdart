import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/pet_repository.dart';

import '../helpers/fake_supabase.dart';

/// 공동보호자 초대 — **상대의 가입 여부가 클라이언트로 새지 않는가.**
///
/// 예전에는 서버가 `registered: true|false` 를 돌려주고 화면이 그걸로 문구를 갈랐다.
/// 초대자에게는 사소한 편의였지만, 번호만 바꿔 부르면 "이 번호가 PawMate 회원인가" 를
/// 무제한으로 캐낼 수 있는 오라클이었다(pmdb 0032 §9.2).
///
/// 서버는 이제 응답을 통일했다. 여기서 못 박는 건 **클라이언트가 그 값을 다시 쓰기
/// 시작하지 못하게** 하는 것이다 — 서버가 실수로(혹은 롤백으로) 다시 실어 보내도
/// 화면까지 흘러가지 않아야 한다.
void main() {
  setUpAll(FakeSupabase.init);
  setUp(FakeSupabase.reset);

  final repo = PetRepository.instance;

  group('invite — 가입 여부 비노출', () {
    test('성공하면 아무것도 돌려주지 않는다(반환 타입이 void)', () async {
      FakeSupabase.on('invite-guardian', (_) => {'ok': true});
      await expectLater(repo.invite('pet-1', '01012345678'), completes);
    });

    test('서버가 registered 를 다시 실어 보내도 호출부가 받을 값이 없다', () async {
      // 회귀 방지의 핵심. 응답에 값이 있어도 API 표면에 통로가 없어야 한다.
      FakeSupabase.on(
        'invite-guardian',
        (_) => {'ok': true, 'registered': true, 'sms': 'sent'},
      );
      final result = repo.invite('pet-1', '01012345678');
      expect(result, isA<Future<void>>());
      await result;
    });

    test('요청에 petId·전화번호가 실린다', () async {
      FakeSupabase.on('invite-guardian', (_) => {'ok': true});
      await repo.invite('pet-42', '01099998888');
      final body = FakeSupabase.requests.last.body;
      expect(body, contains('pet-42'));
      expect(body, contains('01099998888'));
    });
  });

  group('invite — 오류 매핑', () {
    Future<void> expectStateError(int status, String code, String want) async {
      FakeSupabase.on(
        'invite-guardian',
        (_) => FakeSupabase.error(status, {'error': code}),
      );
      await expectLater(
        repo.invite('pet-1', '01012345678'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', want)),
      );
    }

    test('하루 상한 초과(429)는 rate_limited 로 온다', () async {
      // 이 상한이 열거를 묶는 장치다 — 화면이 이걸 "실패했어요" 로 뭉개면
      // 사용자는 왜 막혔는지 모르고, 우리는 상한이 도는지도 모른다.
      await expectStateError(429, 'rate_limited', 'rate_limited');
    });

    test('중복 초대(409)는 already_invited', () async {
      await expectStateError(409, 'already_invited', 'already_invited');
    });

    test('본인 번호(400)는 self_invite', () async {
      await expectStateError(400, 'self_invite', 'self_invite');
    });

    test('모르는 오류는 그대로 올려보낸다(삼키지 않는다)', () async {
      FakeSupabase.on(
        'invite-guardian',
        (_) => FakeSupabase.error(500, {'error': 'internal_error'}),
      );
      await expectLater(
        repo.invite('pet-1', '01012345678'),
        throwsA(isNot(isA<StateError>())),
      );
    });
  });
}
