import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawmate/services/upload_progress.dart';

/// 보낸 요청을 붙잡아 두고, 바디를 실제로 흘려 소비하는 가짜 클라이언트.
class _CapturingClient extends http.BaseClient {
  http.BaseRequest? seen;
  List<int> body = const [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    seen = request;
    body = await request.finalize().toBytes();
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}

/// 청크를 나눠 내보내는 요청 — 진행이 여러 번 보고되는지 보려면 필요하다.
class _ChunkedRequest extends http.BaseRequest {
  _ChunkedRequest(super.method, super.url, this._chunks) {
    contentLength = _chunks.fold<int>(0, (n, c) => n + c.length);
  }
  final List<List<int>> _chunks;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(Stream.fromIterable(_chunks));
  }
}

void main() {
  final url = Uri.parse(
    'https://x.supabase.co/storage/v1/object/media/u/p/1.mp4',
  );

  test('감시 중인 경로가 없으면 요청을 그대로 흘려보낸다', () async {
    final inner = _CapturingClient();
    final client = UploadProgressClient(inner);

    await client.send(_ChunkedRequest('POST', url, [utf8.encode('hello')]));

    expect(inner.seen, isNotNull);
    expect(utf8.decode(inner.body), 'hello');
  });

  test('감시 중인 경로면 누적 전송량을 보고한다', () async {
    final inner = _CapturingClient();
    final client = UploadProgressClient(inner);
    final seen = <double>[];
    client.watch('u/p/1.mp4', (sent, total) => seen.add(sent / total));

    await client.send(
      _ChunkedRequest('POST', url, [
        Uint8List(10),
        Uint8List(10),
        Uint8List(20),
      ]),
    );

    // 바디는 온전히 전달되어야 한다 — 세는 것이 흐름을 바꾸면 안 된다.
    expect(inner.body.length, 40);
    expect(seen, [0.25, 0.5, 1.0]);
  });

  test('다른 경로의 업로드는 이 감시자를 건드리지 않는다', () async {
    final inner = _CapturingClient();
    final client = UploadProgressClient(inner);
    var calls = 0;
    client.watch('u/p/1.mp4', (_, _) => calls++);

    // 나란히 올라가는 포스터(#279) — 큰 영상의 진행률을 덮어쓰면 안 된다.
    await client.send(
      _ChunkedRequest(
        'POST',
        Uri.parse('https://x.supabase.co/storage/v1/object/media/u/p/2.jpg'),
        [Uint8List(10)],
      ),
    );

    expect(calls, 0);
    expect(inner.body.length, 10);
  });

  test('멀티파트 boundary 헤더가 보존된다', () async {
    // MultipartRequest 는 boundary 를 **finalize 시점에** 만들고 그때 자기
    // content-type 헤더에 적는다. 래퍼가 생성자에서 헤더를 복사하면 그 헤더가
    // 빠진 채 나가고 서버는 바디를 파싱하지 못한다(실기기 업로드 실패 원인).
    final inner = _CapturingClient();
    final client = UploadProgressClient(inner);
    client.watch('u/p/1.mp4', (_, _) {});

    final req = http.MultipartRequest(
      'POST',
      url,
    )..files.add(http.MultipartFile.fromBytes('', Uint8List(32), filename: ''));
    await client.send(req);

    final ct = inner.seen!.headers['content-type'];
    expect(ct, isNotNull);
    expect(ct, startsWith('multipart/form-data; boundary='));
    // 실제로 나간 바디의 경계와 헤더의 경계가 같아야 한다.
    final boundary = ct!.split('boundary=').last;
    expect(utf8.decode(inner.body), contains(boundary));
  });

  test('해제하면 더 이상 보고하지 않는다', () async {
    final inner = _CapturingClient();
    final client = UploadProgressClient(inner);
    var calls = 0;
    final unwatch = client.watch('u/p/1.mp4', (_, _) => calls++);
    unwatch();

    await client.send(_ChunkedRequest('POST', url, [Uint8List(10)]));

    expect(calls, 0);
  });

  test('길이를 모르는 요청은 감시 중이어도 그대로 지나간다', () async {
    final inner = _CapturingClient();
    final client = UploadProgressClient(inner);
    var calls = 0;
    client.watch('u/p/1.mp4', (_, _) => calls++);

    // contentLength 를 주지 않는 요청(스트리밍 등) — 분모가 없으니 셀 수 없다.
    final req = http.StreamedRequest('POST', url)..sink.add(utf8.encode('hi'));
    unawaited(req.sink.close());
    await client.send(req);

    expect(calls, 0);
    expect(utf8.decode(inner.body), 'hi');
  });
}
