import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'session.dart';

/// 이미지 선택 + Supabase Storage(media 버킷) 업로드.
/// 경로 규약: `<uid>/<category>/<timestamp>.<ext>` (RLS: 첫 폴더 = 내 uid).
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _c => Supabase.instance.client;

  /// 갤러리에서 이미지 1장 선택 (적당히 리사이즈/압축).
  Future<XFile?> pickImage() => _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );

  /// 업로드 후 공개 URL/메타 반환.
  Future<UploadedImage> upload(XFile file, {required String category}) async {
    final uid = SessionManager.instance.user?.id;
    if (uid == null) throw StateError('로그인이 필요합니다');

    final bytes = await file.readAsBytes();
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    final mime = file.mimeType ?? 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    final path =
        '$uid/$category/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _c.storage.from('media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    final url = _c.storage.from('media').getPublicUrl(path);
    return UploadedImage(url: url, mime: mime, size: bytes.length);
  }
}

class UploadedImage {
  final String url;
  final String mime;
  final int size;
  const UploadedImage({required this.url, required this.mime, required this.size});
}
