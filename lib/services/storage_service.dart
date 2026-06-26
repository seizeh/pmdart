import 'dart:typed_data';

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

  /// 게시글 사진 실존 검증용: 카메라만(갤러리 진입 불가) 방금 찍은 1장.
  /// EXIF 위치는 신뢰하지 않으므로(위치는 geolocator 로 별도 취득) 메타데이터 요청 안 함.
  Future<XFile?> capturePostPhoto() => _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
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

  /// 이미 가공된 바이트(예: 크롭된 이미지)를 업로드. 공개 URL/메타 반환.
  Future<UploadedImage> uploadBytes(
    Uint8List bytes, {
    required String category,
    String ext = 'png',
    String mime = 'image/png',
  }) async {
    final uid = SessionManager.instance.user?.id;
    if (uid == null) throw StateError('로그인이 필요합니다');
    final path = '$uid/$category/${DateTime.now().millisecondsSinceEpoch}.$ext';
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
