import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/storage_service.dart';

/// media 버킷 업로드 사전 검사.
///
/// 진짜 관문은 서버(버킷 `allowed_mime_types` + `file_size_limit`)다. 여기서 못 박는 건
/// **클라이언트 목록이 서버보다 넓어지지 않는 것** — 넓어지면 통과시켜 놓고 스토리지가
/// 튕겨서, 사용자에게는 이유 없는 "업로드 실패" 만 남는다.
void main() {
  group('허용되는 것', () {
    test('앱이 실제로 만드는 이미지 타입', () {
      for (final m in ['image/jpeg', 'image/png', 'image/webp', 'image/gif']) {
        expect(mediaUploadRejection(m, 1024), isNull, reason: m);
      }
    });

    test('HEIC/HEIF — 디코드 실패 시 원본이 그대로 올라가는 경로가 있다', () {
      // _normalizePhoto 가 비-Safari 의 HEIC 디코드에 실패하면 원본을 반환한다.
      // 이걸 빼면 그 사용자만 조용히 업로드가 깨진다.
      expect(mediaUploadRejection('image/heic', 1024), isNull);
      expect(mediaUploadRejection('image/heif', 1024), isNull);
    });

    test('영상 컨테이너 — iOS(quicktime)·안드로이드(mp4/webm/3gpp)', () {
      for (final m in [
        'video/mp4',
        'video/quicktime',
        'video/webm',
        'video/3gpp',
      ]) {
        expect(mediaUploadRejection(m, 1024), isNull, reason: m);
      }
    });

    test('대소문자·공백은 정규화해서 본다', () {
      expect(mediaUploadRejection(' IMAGE/JPEG ', 1024), isNull);
    });
  });

  group('막아야 하는 것', () {
    test('text/html — 공개 CDN 에서 살아 있는 페이지가 된다', () {
      expect(mediaUploadRejection('text/html', 1024), isNotNull);
    });

    test('image/svg+xml — 이미지처럼 보이지만 스크립트를 품는다', () {
      // image/* 와일드카드를 쓰지 않는 이유가 이 한 줄이다.
      expect(mediaUploadRejection('image/svg+xml', 1024), isNotNull);
    });

    test('실행 파일·임의 바이너리', () {
      for (final m in [
        'application/octet-stream',
        'application/pdf',
        'application/javascript',
        'text/plain',
      ]) {
        expect(mediaUploadRejection(m, 1024), isNotNull, reason: m);
      }
    });

    test('빈 MIME 은 통과시키지 않는다', () {
      expect(mediaUploadRejection('', 1024), isNotNull);
    });
  });

  group('크기', () {
    test('상한(100MB)까지는 통과한다', () {
      expect(mediaUploadRejection('image/jpeg', kMediaMaxObjectBytes), isNull);
    });

    test('상한을 넘으면 이유를 알려 준다', () {
      final msg = mediaUploadRejection('image/jpeg', kMediaMaxObjectBytes + 1);
      expect(msg, isNotNull);
      expect(msg, contains('100MB'));
    });

    test('형식이 틀리면 크기보다 형식을 먼저 알려 준다', () {
      // 둘 다 틀렸을 때 "크다" 고만 하면 형식을 줄여도 계속 실패한다.
      final msg = mediaUploadRejection('text/html', kMediaMaxObjectBytes + 1);
      expect(msg, contains('형식'));
    });
  });
}
