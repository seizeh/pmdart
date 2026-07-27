/// 위젯 테스트에서 `Image.network`/`NetworkImage` 가 실제 이미지를 받도록
/// HttpClient 를 대체하는 헬퍼 — 원본 비율(가로/세로)에 반응하는 UI 검증용.
/// (flutter_test 기본 클라이언트는 400 을 돌려줘 이미지가 로드되지 않는다.)
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// [width]×[height] 단색 PNG 를 모든 요청에 돌려주도록 전역 HttpOverrides 를
/// 설치한다. 반환값을 `addTearDown` 에 넘겨 원복할 것.
Future<void Function()> installFakeNetworkImage({
  required int width,
  required int height,
}) async {
  final png = await _png(width: width, height: height);
  final previous = HttpOverrides.current;
  HttpOverrides.global = _ImageHttpOverrides(png);
  return () => HttpOverrides.global = previous;
}

Future<Uint8List> _png({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366FF),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _ImageHttpOverrides extends HttpOverrides {
  _ImageHttpOverrides(this.bytes);
  final Uint8List bytes;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(bytes);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.bytes);
  final Uint8List bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(bytes, url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.bytes, this.uri);
  final Uint8List bytes;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.bytes);
  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
