import 'package:http/http.dart' as http;

/// 업로드 진행률 — Supabase Storage 클라이언트에는 진행 콜백이 없다.
///
/// `uploadBinary` 는 바이트를 통째로 넘기는 단일 요청이라 "몇 %" 를 알 방법이
/// 없어 보이지만, `Supabase.initialize(httpClient:)` 로 넣은 클라이언트가 스토리지
/// 멀티파트 요청까지 그대로 지나간다(supabase 2.12 `supabase_client.dart` 에서
/// `_httpClient` 를 StorageClient 로 넘긴다). 그래서 **요청 바디 스트림을 세면**
/// 실제 전송량이 나온다.
///
/// ⚠️ 세는 것은 소켓으로 넘긴 바이트지 서버가 받았다고 확인한 바이트가 아니다.
/// 마지막 몇 %는 실제보다 빨리 100%에 닿을 수 있다. 진행 표시용으로는 충분하다.
///
/// 웹은 XHR 이라 스트림이 한 번에 소진되어 0 → 100 으로 튄다(무해 — 표시가
/// 거칠어질 뿐이고, 웹에서 큰 파일을 올리는 경로는 드물다).
class UploadProgressClient extends http.BaseClient {
  UploadProgressClient(this._inner);

  final http.Client _inner;

  /// 스토리지 오브젝트 경로 → 진행 콜백. 경로로 거르는 이유는 **동시 업로드**
  /// 때문이다 — 영상과 포스터가 나란히 올라가므로(#279) 구분하지 않으면 작은
  /// 포스터가 큰 영상의 진행률을 덮어쓴다.
  final _watchers = <String, void Function(int sent, int total)>{};

  /// [path] 업로드가 지나갈 때 진행을 받는다. 반환값을 호출하면 해제된다.
  void Function() watch(
    String path,
    void Function(int sent, int total) onProgress,
  ) {
    _watchers[path] = onProgress;
    return () => _watchers.remove(path);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final total = request.contentLength;
    if (_watchers.isEmpty || total == null || total <= 0) {
      return _inner.send(request);
    }
    // 업로드 URL 은 `.../object/<bucket>/<path>` 형태다.
    final urlPath = Uri.decodeComponent(request.url.path);
    final key = _watchers.keys.firstWhere(urlPath.endsWith, orElse: () => '');
    if (key.isEmpty) return _inner.send(request);

    final onProgress = _watchers[key]!;
    return _inner.send(
      _CountingRequest(request, (sent) {
        // 멀티파트 경계·헤더가 섞여 total 을 살짝 넘을 수 있다 — 잘라 준다.
        onProgress(sent > total ? total : sent, total);
      }),
    );
  }

  @override
  void close() {
    _watchers.clear();
    _inner.close();
    super.close();
  }
}

/// 바디를 흘려보내면서 누적 전송량을 알려 주는 요청 래퍼.
class _CountingRequest extends http.BaseRequest {
  _CountingRequest(this._inner, this._onSent)
    : super(_inner.method, _inner.url) {
    headers.addAll(_inner.headers);
    followRedirects = _inner.followRedirects;
    maxRedirects = _inner.maxRedirects;
    persistentConnection = _inner.persistentConnection;
  }

  final http.BaseRequest _inner;
  final void Function(int sent) _onSent;

  // 길이는 원 요청이 정본이다(멀티파트 경계 포함). 세터는 무시 —
  // BaseRequest 생성 직후 http 내부가 건드리지 않도록 막아 둔다.
  @override
  int? get contentLength => _inner.contentLength;
  @override
  set contentLength(int? value) {}

  @override
  http.ByteStream finalize() {
    super.finalize();
    var sent = 0;
    return http.ByteStream(
      _inner.finalize().map((chunk) {
        sent += chunk.length;
        _onSent(sent);
        return chunk;
      }),
    );
  }
}
