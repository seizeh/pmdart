import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'error_reporter.dart';
import 'session.dart';

/// 이미지 선택 + Supabase Storage(media 버킷) 업로드.
/// 경로 규약: `<uid>/<category>/<timestamp>.<ext>` (RLS: 첫 폴더 = 내 uid).
/// media 버킷이 받아 주는 MIME — **서버 설정과 같은 목록**이다
/// (pmdb `20260804200000_media_bucket_limits.sql` 의 `allowed_mime_types`).
///
/// 공개 버킷이라 저장된 content-type 이 그대로 서빙된다. 그래서 진짜 관문은 서버(버킷)고,
/// 여기서 먼저 보는 이유는 **거절 이유를 사람 말로 알려 주기 위해서**다 — 검사가 없으면
/// 스토리지가 415/413 을 던지고 화면에는 "업로드 실패" 만 남는다.
///
/// ⚠️ 서버 목록이 바뀌면 여기도 같이 고칠 것. 넓히는 방향으로 어긋나면 무의미해진다
/// (통과시켜 놓고 서버에서 튕긴다).
const Set<String> kMediaAllowedMimes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif',
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'video/3gpp',
};

/// media 버킷 객체 하나의 상한(서버 `file_size_limit` 과 같은 값).
const int kMediaMaxObjectBytes = 100 * 1024 * 1024;

/// 업로드가 거절될 이유를 미리 알려 준다. 문제없으면 null.
String? mediaUploadRejection(String mime, int bytes) {
  if (!kMediaAllowedMimes.contains(mime.trim().toLowerCase())) {
    return '이 형식($mime)은 올릴 수 없어요';
  }
  if (bytes > kMediaMaxObjectBytes) {
    return '파일이 너무 커요 — 100MB 이하만 올릴 수 있어요';
  }
  return null;
}

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _c => Supabase.instance.client;

  /// 사진 한 장의 **긴 변** 상한 — 가로·세로 양쪽에 건다.
  ///
  /// 종전에는 `maxWidth` 만 걸었는데, 그러면 **세로로 긴 요즘 폰 사진은 축소가
  /// 아예 일어나지 않는다** — 1206×2622 사진은 가로가 1600 미만이라 그대로
  /// 통과했다(실측: 5.4MB PNG 가 무보정으로 업로드 대기). `maxWidth`/`maxHeight`
  /// 는 '이 안에 맞추기'(비율 유지·확대 없음)라 둘 다 주면 긴 변이 상한이 된다.
  static const double _photoEdge = 1600;

  /// 서류는 작은 글씨가 읽혀야 승인 심사가 가능하므로 더 크게 둔다.
  static const double _docEdge = 2400;

  /// 이보다 크면 품질을 한 단계 낮춰 다시 인코딩한다.
  static const int _recompressOverBytes = 2 * 1024 * 1024;

  /// 갤러리에서 이미지 1장 선택 (적당히 리사이즈/압축).
  Future<XFile?> pickImage({double edge = _photoEdge}) async {
    final f = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: edge,
      maxHeight: edge,
      imageQuality: 85,
    );
    return f == null ? null : _normalizePhoto(f);
  }

  /// 갤러리에서 여러 장 선택(후기용 — 미리 찍은 사진 허용).
  Future<List<XFile>> pickImages() async {
    final files = await _picker.pickMultiImage(
      maxWidth: _photoEdge,
      maxHeight: _photoEdge,
      imageQuality: 85,
    );
    return Future.wait(files.map(_normalizePhoto));
  }

  /// 업로드 직전 정규화 — 사진이 PNG 로 새어 나가는 것을 막는 **안전망**.
  ///
  /// 웹의 picker 는 canvas 로 리사이즈하는데 `toBlob(type, quality)` 의 quality 가
  /// **JPEG/WebP 에만** 적용된다. PNG 로 들어오면 PNG 로 재인코딩되어 오히려
  /// 커질 수 있다(실측: 526KB → 682KB, 130%).
  ///
  /// ⚠️ **네이티브도 예외가 아니다.** "picker 가 imageQuality 를 주면 알아서
  /// JPEG 로 바꾼다"고 보고 웹에만 걸었다가 틀린 것으로 드러났다 — 프로덕션
  /// media 버킷의 PNG 19장(평균 3.8MB, 최대 14.2MB)은 웹 배포 **이전** 날짜의
  /// 앱 업로드였다. 긴 변 상한이 걸리지 않으면 리사이즈 자체가 일어나지 않고,
  /// 리사이즈가 없으면 재인코딩도 없어 원본 PNG 가 그대로 올라간다.
  /// 상한을 고친 지금은 대부분 JPEG 로 나오지만, 안전망은 양쪽에 둔다.
  ///
  /// 실패하면 원본을 그대로 반환한다. 업로드 자체를 막지는 않는다(종전과 동일).
  Future<XFile> _normalizePhoto(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final isJpeg =
          (file.mimeType ?? '').contains('jpeg') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg');
      final tooBig = bytes.length > _recompressOverBytes;
      if (isJpeg && !tooBig) return file; // 흔한 경로 — 그대로 둔다

      final out = await FlutterImageCompress.compressWithList(
        bytes,
        // 이미 picker 가 긴 변을 줄였으므로 여기서 또 줄이지 않는다.
        // ⚠️ 이 패키지의 minWidth/minHeight 는 '짧은 변 하한'이라 작은 값을 주면
        //    과하게 축소된다. 크게 줘야 '축소 없음'이 된다.
        minWidth: 100000,
        minHeight: 100000,
        quality: tooBig ? 70 : 85,
        format: CompressFormat.jpeg,
      );
      // 이득이 없으면(투명 PNG 등) 원본을 지킨다.
      if (out.isEmpty || out.length >= bytes.length) return file;
      final base = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;
      return XFile.fromData(
        out,
        name: '$base.jpg',
        mimeType: 'image/jpeg',
        length: out.length,
      );
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'storage.transcodeHeic',
        why: '디코드 실패(비-Safari 의 HEIC 등) — 원본을 그대로 올린다',
      );
      return file;
    }
  }

  /// 신원 인증용: 카메라 영상만(갤러리 진입 불가). 무작위 임무 수행 영상(~11초).
  Future<XFile?> capturePetVideo() => _picker.pickVideo(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
    maxDuration: const Duration(seconds: 11),
  );

  /// 첨부 영상 상한(서버 CHECK 와 동일 — 100MB). 초과 시 업로드 전에 거른다.
  static const int maxVideoBytes = 100 * 1024 * 1024;

  /// 첨부 영상을 다시 인코딩할 화질 — 720p.
  ///
  /// 피드·상세는 세로 전체화면 재생이라 720p 면 충분하고, 요즘 폰이 찍는 1080p·4K
  /// 원본은 그대로 올리면 첨부 한 번에 수십 MB 다(실측 14.7MB / 2분).
  static const VideoQuality _videoQuality = VideoQuality.Res1280x720Quality;

  /// 이보다 작으면 재인코딩하지 않는다 — 인코딩에 드는 시간이 업로드 절감분보다
  /// 커지는 구간이다. 이미 작은 영상을 굳이 다시 굽지 않는다.
  static const int _videoCompressOverBytes = 6 * 1024 * 1024;

  /// 갤러리에서 첨부용 동영상 1개 선택.
  ///
  /// ⚠️ `maxDuration` 은 **갤러리 선택에 적용되지 않는다.** iOS 는 PHPicker 경로가
  /// 이 값을 쓰지 않고(FLTImagePickerPlugin.m), Android 도 촬영 인텐트에만 건다
  /// (ImagePickerDelegate.java). 남겨 둔 것은 iOS 13 이하의 UIImagePicker 폴백
  /// 때문이고, 실질 방어는 100MB 상한이다.
  Future<XFile?> pickVideo() async {
    final f = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    return f == null ? null : _normalizeVideo(f);
  }

  /// 업로드 전 영상 재인코딩 — 사진의 [_normalizePhoto] 와 같은 자리다.
  ///
  /// 종전에는 영상만 아무 가공 없이 원본이 올라갔다. 사진은 긴 변 1600 으로 줄이고
  /// 다시 굽는데 영상은 picker 가 준 파일을 그대로 넘겼다.
  ///
  /// 이득은 업로드 시간보다 **보는 쪽**에서 크다 — 피드를 스크롤하는 모든 사람이
  /// 그 바이트를 내려받는다. iOS 구현은 `shouldOptimizeForNetworkUse` 로 내보내므로
  /// 전부 받기 전에 재생이 시작되고, 출력이 mp4 라 .mov 보다 브라우저 호환도 낫다.
  ///
  /// 실패하거나 이득이 없으면 **원본을 그대로 반환**한다. 첨부 자체를 막지 않는다.
  Future<XFile> _normalizeVideo(XFile file) async {
    // 웹은 이 플러그인 구현이 없다(android/ios/macos 만). 원본으로 간다.
    if (kIsWeb) return file;
    try {
      final length = await file.length();
      if (length <= _videoCompressOverBytes) return file;

      final info = await VideoCompress.compressVideo(
        file.path,
        quality: _videoQuality,
        // picker 가 준 임시 복사본이지 사용자의 원본이 아니지만, 그래도 우리가
        // 지울 파일은 아니다(같은 파일을 다시 고르면 picker 가 또 복사한다).
        deleteOrigin: false,
      );
      final out = info?.path;
      // 취소됐거나(isCancel) 실패하면 null·빈 경로가 온다.
      if (out == null || out.isEmpty || info?.isCancel == true) return file;

      final compressed = XFile(out, mimeType: 'video/mp4');
      // 이미 잘 압축된 영상은 다시 구우면 오히려 커진다 — 그럴 땐 원본을 지킨다.
      if (await compressed.length() >= length) return file;
      return compressed;
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'storage.normalizeVideo',
        why: '영상 재인코딩 실패 — 원본을 그대로 올린다(첨부는 계속된다)',
      );
      return file;
    }
  }

  /// 게시글 사진 실존 검증용: 카메라만(갤러리 진입 불가) 방금 찍은 1장.
  /// EXIF 위치는 신뢰하지 않으므로(위치는 geolocator 로 별도 취득) 메타데이터 요청 안 함.
  Future<XFile?> capturePostPhoto() async {
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: _photoEdge,
      maxHeight: _photoEdge,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return f == null ? null : _normalizePhoto(f);
  }

  /// 업로드 후 공개 URL/메타 반환.
  Future<UploadedImage> upload(XFile file, {required String category}) async {
    final uid = SessionManager.instance.storageUserId;
    if (uid == null) throw StateError('로그인이 필요합니다');

    final bytes = await file.readAsBytes();
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    final mime = file.mimeType ?? 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    final reject = mediaUploadRejection(mime, bytes.length);
    if (reject != null) throw StateError(reject);
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
    final uid = SessionManager.instance.storageUserId;
    if (uid == null) throw StateError('로그인이 필요합니다');
    final reject = mediaUploadRejection(mime, bytes.length);
    if (reject != null) throw StateError(reject);
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
    final uid = SessionManager.instance.storageUserId;
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
    final reject = mediaUploadRejection(mime, bytes.length);
    if (reject != null) throw StateError(reject);
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
    // 웹은 video_thumbnail 구현이 없다(MissingPluginException) — 아래 catch 가
    // 삼키긴 하지만 무의미한 왕복이라 아예 건너뛴다. 표시 쪽 폴백이 받는다.
    String? thumbUrl;
    try {
      final poster = kIsWeb
          ? null
          : await VideoThumbnail.thumbnailData(
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
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'storage.videoPoster',
        why: '포스터 생성 실패 — 표시 쪽이 기본 썸네일로 폴백한다',
      );
    }

    return UploadedVideo(
      url: url,
      mime: mime,
      size: bytes.length,
      thumbUrl: thumbUrl,
      path: path,
    );
  }

  /// 공개 URL 에서 media 버킷 내 경로 추출. media 공개 URL 형식이 아니면 null.
  static String? mediaPathFromUrl(String url) {
    const marker = '/object/public/media/';
    final i = url.indexOf(marker);
    if (i < 0) return null;
    final path = url.substring(i + marker.length);
    final q = path.indexOf('?');
    return q < 0 ? path : path.substring(0, q);
  }

  /// 더 이상 참조되지 않을 업로드 파일을 최선 노력으로 삭제(#233).
  ///
  /// DB 쓰기 실패 보상·교체된 구 사진 정리용. 실패해도 기능엔 영향이 없다 —
  /// 남으면 공개 URL 고아 파일이고, 최후 안전망은 서버측 청소 몫이다.
  Future<void> discardByUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final path = mediaPathFromUrl(url);
    if (path == null) return;
    try {
      await _c.storage.from('media').remove([path]);
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'storage.discard',
        why: '고아 파일 정리 실패 — 남아도 기능 무해, 서버측 청소가 안전망',
      );
    }
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

  /// 갤러리 사진을 서류로 선택 — 휴대폰으로 찍은 등록증용.
  /// 사진과 달리 [_docEdge] 로 크게 남긴다 — 작은 글씨가 뭉개지면 승인 심사를 못 한다.
  Future<PickedDoc?> pickDocumentFromGallery() async {
    final f = await pickImage(edge: _docEdge);
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
    final uid = SessionManager.instance.storageUserId;
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
    } catch (e, st) {
      // 사업자 서류 열람 실패 — 관리자 심사가 막힌다.
      ErrorReporter.report(
        e,
        where: 'storage.signedUrl.businessDocs',
        stackTrace: st,
      );
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
