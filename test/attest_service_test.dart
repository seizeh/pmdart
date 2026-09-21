import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/attest_service.dart';

/// AttestService — 본문 해시·헤더 조립·실패 강등(빈 헤더).
///
/// iOS 등록·assertion 경로는 Supabase 초기화·보안 저장소가 필요해 여기서 재지
/// 않는다(실기기 검증 항목). 여기서 못 박는 것은 서버(_shared/attest.ts)와의
/// **해시 형식 계약**과, 채널 실패가 검증 흐름을 깨지 않는다는 강등 계약이다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pawmate/attest');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AttestService.instance.debugReset();
  });

  group('해시 계약(서버 bytesToB64url 과 동일)', () {
    test('clientDataHash = SHA256(본문 utf8)', () {
      const body = '{"lat":37.2,"lng":127.07}';
      expect(
        AttestService.clientDataHash(body),
        sha256.convert(utf8.encode(body)).bytes,
      );
    });

    test('requestHash = base64url(SHA256), 패딩 없음', () {
      const body = '{"lat":37.2}';
      final hash = AttestService.requestHashB64Url(body);
      expect(hash, isNot(contains('=')));
      expect(hash, isNot(contains('+')));
      expect(hash, isNot(contains('/')));
      // 표준 base64 로 복원해 같은 바이트인지 확인.
      final padded =
          hash.replaceAll('-', '+').replaceAll('_', '/') +
          '=' * ((4 - hash.length % 4) % 4);
      expect(base64Decode(padded), sha256.convert(utf8.encode(body)).bytes);
    });
  });

  group('android 헤더', () {
    test('토큰을 x-attest 헤더로 조립하고 requestHash 를 전달한다', () async {
      String? seenHash;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'requestIntegrityToken');
            seenHash = (call.arguments as Map)['requestHash'] as String?;
            return 'integrity-token-123';
          });

      AttestService.instance.debugPlatform = 'android';
      const body = '{"lat":1,"lng":2}';
      final headers = await AttestService.instance.headersFor(body);

      expect(headers, {
        'x-attest-platform': 'android',
        'x-attest-token': 'integrity-token-123',
      });
      expect(seenHash, AttestService.requestHashB64Url(body));
    });

    test('채널 오류는 빈 헤더로 강등(검증 흐름을 깨지 않는다)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'prepare_failed', message: 'GMS 없음');
          });

      AttestService.instance.debugPlatform = 'android';
      final headers = await AttestService.instance.headersFor('{"lat":1}');
      expect(headers, isEmpty);
    });

    test('빈 토큰도 빈 헤더로 강등', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => '');

      AttestService.instance.debugPlatform = 'android';
      final headers = await AttestService.instance.headersFor('{"lat":1}');
      expect(headers, isEmpty);
    });
  });

  group('ios 헤더', () {
    test('미지원 기기(isSupported=false)는 빈 헤더 + 세션 내 재시도 안 함', () async {
      var isSupportedCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isSupported') {
              isSupportedCalls++;
              return false;
            }
            fail('isSupported 외 호출 금지: ${call.method}');
          });

      AttestService.instance.debugPlatform = 'ios';
      expect(await AttestService.instance.headersFor('{"lat":1}'), isEmpty);
      expect(await AttestService.instance.headersFor('{"lat":2}'), isEmpty);
      expect(isSupportedCalls, 1, reason: '실패 후 세션 내 재등록 시도 없음');
    });
  });

  test('미지원 플랫폼(호스트 테스트 환경)은 빈 헤더', () async {
    // debugPlatform 미지정 — 테스트 러너는 iOS/Android 가 아니므로 즉시 빈 맵.
    expect(await AttestService.instance.headersFor('{"lat":1}'), isEmpty);
  });
}
