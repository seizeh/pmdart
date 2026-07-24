import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
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

  /// 갤러리에서 여러 장 선택(후기용 — 미리 찍은 사진 허용).
  Future<List<XFile>> pickImages() =>
      _picker.pickMultiImage(maxWidth: 1600, imageQuality: 85);

  /// 신원 인증용: 카메라 영상만(갤러리 진입 불가). 무작위 임무 수행 영상(~11초).
  Future<XFile?> capturePetVideo() => _picker.pickVideo(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
    maxDuration: const Duration(seconds: 11),
  );

  /// 첨부 영상 상한(서버 CHECK 와 동일 — 100MB). 초과 시 업로드 전에 거른다.
  static const int maxVideoBytes = 100 * 1024 * 1024;

  /// 갤러리에서 첨부용 동영상 1개 선택(최대 60초).
  Future<XFile?> pickVideo() => _picker.pickVideo(
    source: ImageSource.gallery,
    maxDuration: const Duration(seconds: 60),
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
    final path = '$uid/$category/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _c.storage
        .from('media')
        .uploadBinary(
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
    await _c.storage
        .from('media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    final url = _c.storage.from('media').getPublicUrl(path);
    return UploadedImage(url: url, mime: mime, size: bytes.length);
  }

  /// 첨부 동영상 업로드 — 100MB 초과 시 예외. media 버킷에 영상을 올리고,
  /// 첫 프레임으로 포스터(jpeg)를 만들어 함께 업로드한다(포스터 실패는 무해 —
  /// 표시 쪽이 어두운 타일로 폴백).
  Future<UploadedVideo> uploadVideo(
    XFile file, {
    required String category,
  }) async {
    final uid = SessionManager.instance.user?.id;
    if (uid == null) throw StateError('로그인이 필요합니다');

    // 크기 검사 — 전체 바이트를 읽기 전에 길이만 먼저 확인한다.
    final length = await file.length();
    if (length > maxVideoBytes) {
      throw StateError('동영상은 100MB 이하만 첨부할 수 있어요');
    }

    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'mp4';
    final mime =
        file.mimeType ?? (ext == 'mov' ? 'video/quicktime' : 'video/$ext');
    final bytes = await file.readAsBytes();
    final path = '$uid/$category/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _c.storage
        .from('media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    final url = _c.storage.from('media').getPublicUrl(path);

    // 포스터(첫 프레임) — 실패해도 영상 자체는 유효하므로 무시.
    String? thumbUrl;
    try {
      final poster = await VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 1024,
        quality: 75,
      );
      if (poster != null) {
        final up = await uploadBytes(
          poster,
          category: category,
          ext: 'jpg',
          mime: 'image/jpeg',
        );
        thumbUrl = up.url;
      }
    } catch (_) {
      /* 포스터 없이 진행 — 표시 쪽 폴백 */
    }

    return UploadedVideo(
      url: url,
      mime: mime,
      size: bytes.length,
      thumbUrl: thumbUrl,
      path: path,
    );
  }

  // ── 업체 서류(0025 §3.3) — 비공개 business-docs 버킷. 공개 URL 없음, 경로만 저장하고
  //    열람은 signed URL 로만(본인·관리자 RLS SELECT).

  /// 사업자등록증 등 문서 선택 — 사진(jpg/png/webp)과 PDF 허용.
  Future<PickedDoc?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    final f = result?.files.firstOrNull;
    if (f == null || f.bytes == null) return null;
    final ext = (f.extension ?? 'jpg').toLowerCase();
    return PickedDoc(
      bytes: f.bytes!,
      ext: ext,
      mime: ext == 'pdf'
          ? 'application/pdf'
          : 'image/${ext == 'jpg' ? 'jpeg' : ext}',
      name: f.name,
    );
  }

  /// 갤러리 사진을 서류로 선택 — 휴대폰으로 찍은 등록증용(리사이즈/압축 동일).
  Future<PickedDoc?> pickDocumentFromGallery() async {
    final f = await pickImage();
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    var ext = f.name.contains('.')
        ? f.name.split('.').last.toLowerCase()
        : 'jpg';
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) ext = 'jpg';
    return PickedDoc(
      bytes: bytes,
      ext: ext,
      mime: f.mimeType ?? 'image/${ext == 'jpg' ? 'jpeg' : ext}',
      name: f.name,
    );
  }

  /// 비공개 버킷 업로드 — 반환값은 URL 이 아니라 '경로'(`<uid>/<kind>/<ts>.<ext>`).
  Future<String> uploadBusinessDoc(
    PickedDoc doc, {
    required String kind,
  }) async {
    final uid = SessionManager.instance.user?.id;
    if (uid == null) throw StateError('로그인이 필요합니다');
    final path =
        '$uid/$kind/${DateTime.now().millisecondsSinceEpoch}.${doc.ext}';
    await _c.storage
        .from('business-docs')
        .uploadBinary(
          path,
          doc.bytes,
          fileOptions: FileOptions(contentType: doc.mime, upsert: false),
        );
    return path;
  }

  /// 비공개 서류 열람용 signed URL (기본 60초 — 화면 미리보기 용도).
  Future<String?> businessDocSignedUrl(
    String path, {
    int expiresIn = 60,
  }) async {
    try {
      return await _c.storage
          .from('business-docs')
          .createSignedUrl(path, expiresIn);
    } catch (_) {
      return null;
    }
  }
}

class PickedDoc {
  final Uint8List bytes;
  final String ext;
  final String mime;
  final String name;
  const PickedDoc({
    required this.bytes,
    required this.ext,
    required this.mime,
    required this.name,
  });
}

class UploadedImage {
  final String url;
  final String mime;
  final int size;
  const UploadedImage({
    required this.url,
    required this.mime,
    required this.size,
  });
}

/// 업로드된 첨부 동영상 — 영상 공개 URL + 포스터(jpeg) URL(실패 시 null).
/// [path] 는 media 버킷 내 경로(시설 후기 p_videos jsonb 에 함께 저장).
class UploadedVideo {
  final String url;
  final String mime;
  final int size;
  final String? thumbUrl;
  final String path;
  const UploadedVideo({
    required this.url,
    required this.mime,
    required this.size,
    required this.path,
    this.thumbUrl,
  });
}
