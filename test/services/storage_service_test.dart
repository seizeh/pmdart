import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/storage_service.dart';

void main() {
  group('StorageService.mediaPathFromUrl — 공개 URL → 버킷 경로(#233)', () {
    test('표준 공개 URL 에서 경로를 뽑는다', () {
      expect(
        StorageService.mediaPathFromUrl(
          'https://x.supabase.co/storage/v1/object/public/media/u1/chat/1.jpg',
        ),
        'u1/chat/1.jpg',
      );
    });

    test('쿼리스트링(변환 파라미터)은 떼어낸다', () {
      expect(
        StorageService.mediaPathFromUrl(
          'https://x.supabase.co/storage/v1/object/public/media/u1/a.jpg?width=100',
        ),
        'u1/a.jpg',
      );
    });

    test('media 공개 URL 형식이 아니면 null — 엉뚱한 삭제 요청을 막는다', () {
      expect(
        StorageService.mediaPathFromUrl('https://x.co/other/file.jpg'),
        isNull,
      );
      expect(
        StorageService.mediaPathFromUrl(
          'https://x.co/storage/v1/object/public/business-docs/u1/doc.pdf',
        ),
        isNull,
      );
    });
  });
}
