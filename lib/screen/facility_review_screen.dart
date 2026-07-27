import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../models/facility_review.dart';
import '../motion/motion.dart';
import '../services/facility_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import '../widgets/lite_review_auth_sheet.dart';
import '../widgets/media_widgets.dart';

/// 인증 전에 고른 사진 — 업로드는 인증 후에만 가능하다(Storage RLS 가 `<uid>/...`
/// 폴더 기준이라 비로그인은 쓰지 못한다). 미리보기는 바이트로 그린다(웹·앱 공통).
class _PendingPhoto {
  final XFile file;
  final Uint8List bytes;
  const _PendingPhoto(this.file, this.bytes);
}

/// 시설 후기 작성/수정 (0022) — 게시글 작성(post_create_screen)과 같은 디자인
/// 문법: 섹션 라벨·간격·타이포, 앱바 '등록' 액션, 첨부는 바텀시트(사진/동영상).
/// 갤러리 다중 사진 허용(자유 비율 — 크롭 없음). 카페는 작성 시 승격.
/// 저장 성공 시 true 를 pop.
class FacilityReviewScreen extends StatefulWidget {
  final Facility facility;
  final FacilityReview? existing; // 있으면 수정
  const FacilityReviewScreen({
    super.key,
    required this.facility,
    this.existing,
  });

  @override
  State<FacilityReviewScreen> createState() => _FacilityReviewScreenState();
}

class _FacilityReviewScreenState extends State<FacilityReviewScreen> {
  late int _rating = widget.existing?.rating ?? 5;
  late final _contentCtrl = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late final List<String> _photos = [...?widget.existing?.photoUrls];
  // 첨부 동영상(최대 2개) — {url, thumbUrl, path}.
  late final List<ReviewVideo> _videos = [...?widget.existing?.videos];
  // 업체 혜택(할인·사은품) 수령 표시 — 표시광고법 경제적 이해관계 표시(0028 §6).
  late bool _hasIncentive = widget.existing?.hasIncentive ?? false;
  bool _uploading = false;
  bool _uploadingVideo = false;
  bool _submitting = false;

  /// 비로그인 손님이 고른 사진 — 게시 직전 간이 인증을 마친 뒤 한꺼번에 올린다.
  /// 인증을 취소해도 고른 사진이 사라지지 않게 여기 남겨 둔다(초안 보존).
  final List<_PendingPhoto> _pending = [];

  static const _maxPhotos = 5;
  static const _maxVideos = 2;
  final _repo = FacilityReviewRepository.instance;

  /// 비로그인 작성 — 간이 회원(0029) 경로. 게시 시점에만 인증을 요구한다.
  bool get _isGuest => !SessionManager.instance.isLoggedIn;

  /// 사진 개수는 업로드된 것 + 대기 중인 것의 합.
  int get _photoCount => _photos.length + _pending.length;

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 첨부 바텀시트 — 사진/동영상 선택(게시글 작성의 첨부 시트와 동일 문법).
  Future<void> _chooseAttachment() async {
    final canPhoto = _photoCount < _maxPhotos && !_uploading;
    // 동영상은 인코딩·포스터 생성까지 걸려 있어 대기(pending) 처리를 하지 않는다.
    // 비로그인은 사진만 — 인증을 앞당겨 요구하느니 명시적으로 안내한다.
    final canVideo = _videos.length < _maxVideos && !_uploadingVideo && !_isGuest;
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '첨부하기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              enabled: canPhoto,
              leading: Icon(
                Icons.photo_library_outlined,
                color: canPhoto
                    ? context.colors.primaryDark
                    : context.colors.textTertiary,
              ),
              title: const Text('사진'),
              subtitle: Text('자유 비율 · 최대 $_maxPhotos장'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              enabled: canVideo,
              leading: Icon(
                Icons.videocam_outlined,
                color: canVideo
                    ? context.colors.primaryDark
                    : context.colors.textTertiary,
              ),
              title: const Text('동영상'),
              subtitle: Text(
                _isGuest
                    ? '동영상은 회원가입 후 첨부할 수 있어요'
                    : '최대 60초 · 100MB · $_maxVideos개',
              ),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (src == 'photo') return _addPhotos();
    if (src == 'video') return _addVideo();
  }

  Future<void> _addPhotos() async {
    if (_photoCount >= _maxPhotos || _uploading) return;
    final files = await StorageService.instance.pickImages();
    if (files.isEmpty) return;

    // 비로그인은 아직 uid 가 없어 Storage 에 못 쓴다 — 게시 직전 인증 후 올린다.
    if (_isGuest) {
      setState(() => _uploading = true);
      try {
        for (final f in files) {
          if (_photoCount >= _maxPhotos) break;
          _pending.add(_PendingPhoto(f, await f.readAsBytes()));
        }
        if (mounted) setState(() {});
      } catch (_) {
        _toast('사진을 읽지 못했어요');
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      for (final f in files) {
        if (_photos.length >= _maxPhotos) break;
        final up = await StorageService.instance.upload(
          f,
          category: 'facility_review',
        );
        _photos.add(up.url);
      }
      if (mounted) setState(() {});
    } catch (_) {
      _toast('사진 업로드에 실패했어요');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 동영상 선택 → 업로드(포스터 생성 포함). 100MB 초과는 업로드 전에 안내.
  Future<void> _addVideo() async {
    if (_videos.length >= _maxVideos || _uploadingVideo) return;
    final file = await StorageService.instance.pickVideo();
    if (file == null) return;
    setState(() => _uploadingVideo = true);
    try {
      final up = await StorageService.instance.uploadVideo(
        file,
        category: 'facility_review',
      );
      if (!mounted) return;
      setState(
        () => _videos.add(
          ReviewVideo(url: up.url, thumbUrl: up.thumbUrl, path: up.path),
        ),
      );
    } on StateError catch (e) {
      _toast(e.message); // 100MB 초과 등 한국어 안내
    } catch (_) {
      _toast('동영상 업로드에 실패했어요');
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  /// 후기를 매달 facility_id (카페는 승격해서 확보).
  Future<String> _resolveFacilityId() async {
    final f = widget.facility;
    if (!f.isNaver) return f.id;
    return _repo.ensureNaverFacility(
      name: f.name,
      address: f.address,
      phone: f.phone,
      lng: f.lng,
      lat: f.lat,
    );
  }

  /// 게시. 비로그인이면 **여기서** 간이 인증을 받는다 — 쓰기 전에 가입을 요구하면
  /// 대부분 이탈하므로, 다 쓰고 게시를 누르는 순간에만 번호 인증을 청한다(0029).
  ///
  /// 인증을 취소하면 아무것도 잃지 않고 작성 화면으로 돌아온다(별점·본문·사진 유지).
  Future<void> _submit() async {
    setState(() => _submitting = true);

    String? liteToken;
    if (_isGuest) {
      final auth = await showLiteReviewAuthSheet(context);
      if (!mounted) return;
      if (auth == null || auth.token == null) {
        // 취소 — 초안은 그대로 두고 버튼만 되살린다.
        setState(() => _submitting = false);
        return;
      }
      if (auth.userId == null) {
        setState(() => _submitting = false);
        _toast('인증 정보를 받지 못했어요. 다시 시도해주세요');
        return;
      }
      liteToken = auth.token;
      SessionManager.instance.beginLiteSession(liteToken!, auth.userId!);
    }

    try {
      // 인증을 마쳤으니 이제 Storage 에 쓸 수 있다 — 대기 중이던 사진을 올린다.
      for (final p in _pending) {
        final up = await StorageService.instance.upload(
          p.file,
          category: 'facility_review',
        );
        _photos.add(up.url);
      }
      _pending.clear();

      final fid = await _resolveFacilityId();
      await _repo.addReview(
        facilityId: fid,
        rating: _rating,
        body: _contentCtrl.text,
        photoUrls: _photos,
        videos: _videos,
        hasIncentive: _hasIncentive,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e.toString();
      // 자기 업체 후기는 서버가 차단(own_facility) — 안내를 구분한다.
      _toast(
        msg.contains('own_facility')
            ? '내 업체에는 후기를 남길 수 없어요'
            : msg.contains('reverify_required')
            ? '인증이 만료됐어요. 다시 시도해주세요'
            : '후기 저장에 실패했어요',
      );
    } finally {
      // 간이 토큰은 게시 한 건에만 쓰이고 즉시 버린다(저장하지 않는다).
      if (liteToken != null) SessionManager.instance.endLiteSession();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('후기 삭제'),
        content: const Text('이 후기를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      final fid = await _resolveFacilityId();
      await _repo.deleteMine(fid);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('삭제에 실패했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: context.colors.background,
      // 등록은 앱바 액션 — 게시글 작성과 동일 문법.
      appBar: AppBar(
        title: Text(editing ? '후기 수정' : '후기 작성'),
        actions: [
          if (editing)
            IconButton(
              icon: Icon(Icons.delete_outline, color: context.colors.danger),
              tooltip: '후기 삭제',
              onPressed: _submitting ? null : _delete,
            ),
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    editing ? '수정' : '등록',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 시설 이름 + 안내 캡션(게시글 작성의 라벨·캡션 문법).
              Text(
                widget.facility.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '방문 경험을 별점과 후기로 남겨주세요',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('별점'),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    Pressable(
                      scaleTo: 0.85,
                      borderRadius: BorderRadius.circular(100),
                      onTap: () => setState(() => _rating = i),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          i <= _rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 36,
                          color: i <= _rating
                              ? const Color(0xFFFFB300)
                              : context.colors.border,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionLabel('후기'),
              TextField(
                controller: _contentCtrl,
                minLines: 5,
                maxLines: 10,
                maxLength: 1000,
                decoration: const InputDecoration(hintText: '시설에 대한 후기를 남겨주세요'),
              ),
              const SizedBox(height: 12),
              _SectionLabel(
                '사진·동영상  ·  사진 $_photoCount/$_maxPhotos · '
                '동영상 ${_videos.length}/$_maxVideos',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    _thumb(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _photos[i],
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                        ),
                      ),
                      onRemove: () => setState(() => _photos.removeAt(i)),
                    ),
                  // 아직 업로드 전인 사진(비로그인) — 게시 때 함께 올라간다.
                  for (var i = 0; i < _pending.length; i++)
                    _thumb(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _pending[i].bytes,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                        ),
                      ),
                      onRemove: () => setState(() => _pending.removeAt(i)),
                    ),
                  for (var i = 0; i < _videos.length; i++)
                    _thumb(
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: VideoPosterTile(
                          videoUrl: _videos[i].url,
                          posterUrl: _videos[i].thumbUrl,
                          borderRadius: BorderRadius.circular(12),
                          badgeSize: 28,
                          cacheWidth: 200,
                        ),
                      ),
                      onRemove: () => setState(() => _videos.removeAt(i)),
                    ),
                  // 첨부 추가 — 탭하면 사진/동영상 선택 바텀시트.
                  if (_photoCount < _maxPhotos ||
                      _videos.length < _maxVideos)
                    Pressable(
                      borderRadius: BorderRadius.circular(12),
                      onTap: (_uploading || _uploadingVideo)
                          ? null
                          : _chooseAttachment,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: context.colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.colors.border),
                        ),
                        child: (_uploading || _uploadingVideo)
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.add_rounded,
                                size: 26,
                                color: context.colors.textTertiary,
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              // 표시광고법: 대가성 후기는 경제적 이해관계 표시 의무 — 체크 시
              // 후기 카드·상세·공유 뷰어에 '업체 혜택 받고 작성' 배지가 붙는다.
              // 게시글 작성의 선택 카드 문법(선택 시 색 채움 + 테두리 강조).
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _hasIncentive = !_hasIncentive),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _hasIncentive
                        ? context.colors.primarySoft.withValues(alpha: 0.3)
                        : context.colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hasIncentive
                          ? context.colors.primary
                          : context.colors.border,
                      width: _hasIncentive ? 1.5 : 0.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _hasIncentive
                            ? Icons.check_circle
                            : Icons.radio_button_off,
                        color: _hasIncentive
                            ? context.colors.primary
                            : context.colors.textTertiary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '업체로부터 할인·사은품 등 혜택을 받고 작성해요',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textPrimary,
                                height: 1.4,
                              ),
                            ),
                            if (_hasIncentive) ...[
                              const SizedBox(height: 4),
                              Text(
                                '후기에 \'업체 혜택 받고 작성\' 표시가 함께 노출돼요.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.colors.textTertiary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// 첨부 썸네일 + 우상단 제거 버튼(공용).
  Widget _thumb({required Widget child, required VoidCallback onRemove}) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 4,
          top: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// 섹션 라벨 — 게시글 작성 화면과 동일한 타이포.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}
