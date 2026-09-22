import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_reporter.dart';

/// 기기 증명(App Attest / Play Integrity) 헤더 — 좌표 자기신고 보강(pmdb §7.5).
///
/// verify-location / verify-post-photo 요청에 "미변조 정품 앱이 정품 기기에서
/// 보낸 요청"의 증명을 얹는다. 증명은 **요청 본문 SHA-256 에 바인딩**되므로
/// 호출부는 본문을 직접 jsonEncode 한 문자열을 그대로 전송해야 한다(같은 바이트를
/// 서버가 다시 해시한다 — Map 을 넘겨 SDK 가 재인코딩하면 해시가 어긋난다).
///
/// 서버는 현재 **섀도 모드**(기록만, 거절 없음)라 이 헤더는 실패해도 기능에 영향이
/// 없다 — 그래서 모든 실패는 조용히 빈 헤더로 강등한다(미지원 기기·구형 OS·일시
/// 오류). 강제 전환(pmdb ATTEST_ENFORCE) 후에는 이 강등이 곧 인증 실패가 되므로,
/// 전환 PR 에서 attest_required/attest_failed 문구 매핑과 함께 재점검할 것.
class AttestService {
  AttestService._();
  static final AttestService instance = AttestService._();

  static const MethodChannel _channel = MethodChannel('pawmate/attest');
  static const _keyIdStorageKey = 'attest_key_id';
  static const _secure = FlutterSecureStorage();

  /// 채널·플랫폼 대기 상한 — 검증 UX 를 지연시키지 않는다(섀도라 포기해도 무해).
  static const _timeout = Duration(seconds: 4);

  /// iOS 키 등록(1회성, 네트워크 2회 + attest) 상한.
  static const _registerTimeout = Duration(seconds: 10);

  /// 등록 실패 시 이번 세션에는 재시도하지 않는다(매 촬영마다 2 왕복 낭비 방지).
  bool _registrationFailedThisSession = false;

  /// 테스트에서 플랫폼 분기를 강제한다('ios' | 'android').
  @visibleForTesting
  String? debugPlatform;

  /// 테스트 후 상태 초기화.
  @visibleForTesting
  void debugReset() {
    _registrationFailedThisSession = false;
    debugPlatform = null;
  }

  /// 요청 본문에 바인딩된 기기 증명 헤더. 실패·미지원은 빈 맵(헤더 미첨부).
  Future<Map<String, String>> headersFor(String bodyJson) async {
    final platform =
        debugPlatform ??
        (kIsWeb
            ? null
            : (Platform.isIOS
                  ? 'ios'
                  : (Platform.isAndroid ? 'android' : null)));
    if (platform == null) return const {};
    try {
      if (platform == 'ios') return await _iosHeaders(bodyJson);
      return await _androidHeaders(bodyJson);
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'attest.headers',
        why: '서버가 섀도 모드 — 헤더 미첨부는 검증 결과에 영향이 없다',
      );
      return const {};
    }
  }

  /// SHA-256(본문) — App Attest clientDataHash 원료. 서버와 같은 바이트를 해시한다.
  @visibleForTesting
  static Uint8List clientDataHash(String bodyJson) =>
      Uint8List.fromList(sha256.convert(utf8.encode(bodyJson)).bytes);

  /// base64url(SHA-256(본문), 패딩 없음) — Play Integrity requestHash.
  /// 서버(_shared/attest.ts bytesToB64url)와 같은 형식이어야 대조가 성립한다.
  @visibleForTesting
  static String requestHashB64Url(String bodyJson) =>
      base64UrlEncode(clientDataHash(bodyJson)).replaceAll('=', '');

  Future<Map<String, String>> _androidHeaders(String bodyJson) async {
    final token = await _channel
        .invokeMethod<String>('requestIntegrityToken', {
          'requestHash': requestHashB64Url(bodyJson),
        })
        .timeout(_timeout);
    if (token == null || token.isEmpty) return const {};
    return {'x-attest-platform': 'android', 'x-attest-token': token};
  }

  Future<Map<String, String>> _iosHeaders(String bodyJson) async {
    final keyId = await _ensureIosKey();
    if (keyId == null) return const {};
    final assertion = await _channel
        .invokeMethod<Uint8List>('generateAssertion', {
          'keyId': keyId,
          'clientDataHash': clientDataHash(bodyJson),
        })
        .timeout(_timeout);
    if (assertion == null) return const {};
    return {
      'x-attest-platform': 'ios',
      'x-attest-key-id': keyId,
      'x-attest-assertion': base64Encode(assertion),
    };
  }

  /// App Attest 키 확보 — 설치당 1회 등록(attest-register), 이후 보관된 keyId 재사용.
  /// 등록: 챌린지 발급 → generateKey → attestKey(SHA256(챌린지)) → 서버 검증·등록.
  Future<String?> _ensureIosKey() async {
    String? stored;
    try {
      stored = await _secure.read(key: _keyIdStorageKey);
    } catch (e) {
      // 저장소 접근 실패 — 등록 경로로(실패해도 섀도라 무해)
      ErrorReporter.ignored(
        e,
        where: 'attest.keyid.read',
        why: '보관 keyId 를 못 읽으면 재등록하면 된다(서버는 중복 등록 no-op)',
      );
      stored = null;
    }
    if (stored != null && stored.isNotEmpty) return stored;
    if (_registrationFailedThisSession) return null;

    try {
      return await _registerIosKey().timeout(_registerTimeout);
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'attest.register',
        why: '등록 실패는 헤더 미첨부(absent)로 남을 뿐 — 세션당 1회만 재시도',
      );
      _registrationFailedThisSession = true;
      return null;
    }
  }

  Future<String?> _registerIosKey() async {
    final supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    if (!supported) {
      _registrationFailedThisSession = true;
      return null;
    }
    final functions = Supabase.instance.client.functions;

    final challengeRes = await functions.invoke(
      'attest-register',
      body: {'phase': 'challenge'},
    );
    final challenge = (challengeRes.data as Map?)?['challenge'] as String?;
    if (challenge == null || challenge.isEmpty) {
      throw StateError('challenge 발급 실패');
    }

    final keyId = await _channel.invokeMethod<String>('generateKey');
    if (keyId == null || keyId.isEmpty) throw StateError('generateKey 실패');

    final attestation = await _channel.invokeMethod<Uint8List>('attestKey', {
      'keyId': keyId,
      'clientDataHash': Uint8List.fromList(
        sha256.convert(base64Decode(challenge)).bytes,
      ),
    });
    if (attestation == null) throw StateError('attestKey 실패');

    final registerRes = await functions.invoke(
      'attest-register',
      body: {
        'phase': 'register',
        'keyId': keyId,
        'attestation': base64Encode(attestation),
      },
    );
    if ((registerRes.data as Map?)?['registered'] != true) {
      throw StateError('서버 등록 거절: ${registerRes.data}');
    }

    try {
      await _secure.write(key: _keyIdStorageKey, value: keyId);
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'attest.keyid.write',
        why: '보관 실패 시 다음 실행에서 재등록된다(서버는 키 중복 등록을 no-op 처리)',
      );
    }
    return keyId;
  }
}
