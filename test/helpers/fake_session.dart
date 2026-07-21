/// 세션 관련 테스트 공용 헬퍼 — secure storage 채널 목 + 가짜 JWT.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_secure_storage 플랫폼 채널을 인메모리 맵으로 대체하고
/// 백킹 맵을 반환한다(내용 검증·초기화용). 바인딩 초기화 후 호출할 것.
Map<String, String> installFakeSecureStorage() {
  final store = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.from(store);
          case 'deleteAll':
            store.clear();
            return null;
          case 'containsKey':
            return store.containsKey(key);
        }
        return null;
      });
  return store;
}

/// exp 를 지정한 가짜 HS256 JWT (클라이언트는 payload 의 exp 만 읽는다).
String jwtWithExp(int expEpochSec) {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc({'sub': 'u1', 'exp': expEpochSec})}.sig';
}

int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
