import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:image_picker/image_picker.dart' show XFile;

import '../models/facility_review.dart';
import '../motion/motion.dart';
import '../services/facility_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import '../widgets/blob_background.dart';
import '../widgets/lite_review_auth_sheet.dart';
import '../widgets/media_widgets.dart';
import '../widgets/overlay_icon_button.dart';
import '../widgets/post_media_hero.dart' show MediaOverlayPanel;

/// 인증 전에 고른 사진 — 업로드는 인증 후에만 가능하다(Storage RLS 가 `<uid>/...`
/// 폴더 기준이라 비로그인은 쓰지 못한다). 미리보기는 바이트로 그린다(웹·앱 공통).
class _PendingPhoto {
  final XFile file;
  final Uint8List bytes;
  const _PendingPhoto(this.file, this.bytes);
}

/// 시설 후기 작성/수정 (0022) — 게시글 작성(post_create_screen)과 같은 디자인
/// 문법: 화면이 곧 **전체화면 후기 카드**다. 앱바 제목·뒤로가기 없이 미디어
/// (사진/영상 포스터/블롭)가 화면을 채우고, 하단 오버레이에서 별점·본문·혜택
/// 표시·첨부를 그 자리에서 편집한다. 닫기는 **아래로 쓸어내리기**(또는 시스템
/// 뒤로가기) — [originRect] 로 준 원본으로 축소되며 닫힌다.
/// 갤러리 다중 사진 허용(자유 비율 — 크롭 없음). 카페는 작성 시 승격.
/// 저장 성공 시 true 를 pop.
class FacilityReviewScreen extends StatefulWidget {
  final Facility facility;
  final FacilityReview? existing; // 있으면 수정

  /// 펼쳐지고·축소될 원본 사각형. null 이면 축소 제스처 없이 일반 화면.
  final Rect? originRect;

  /// 축소 안착 시 크로스페이드할 원본 위젯(없으면 콘텐츠만 이동).
  final WidgetBuilder? cardBuilder;

  /// 원본의 모서리 곡률 — 축소 안착 시 곡률이 튀지 않도록 원본과 맞춘다.
  final double cardRadius;

  const FacilityReviewScreen({
    super.key,
    required this.facility,
    this.existing,
    this.originRect,
    this.cardBuilder,
    this.cardRadius = 0,
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

  // 아래로 당기면 원본으로 축소되는 CollapsibleView 용 스크롤 컨트롤러.
  final _scroll = ScrollController();

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
    _scroll.dispose();
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
    final canVideo =
        _videos.length < _maxVideos && !_uploadingVideo && !_isGuest;
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
    // OS 픽커가 떠 있는 동안 정지/차단 게이트나 푸시 라우팅이 라우트를 걷어낼 수
    // 있다 — 그러면 아래 setState 가 defunct State 를 건드린다(#238).
    if (!mounted) return;

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
    if (!mounted) return; // 픽커 대기 중 라우트 제거 가능(#238)
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
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    // 원본에서 펼쳐지고, 아래로 쓸어내리면 그 자리로 축소되며 닫힌다 —
    // 게시글 작성·상세와 같은 래퍼(뒤로가기 버튼이 없는 이유).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: CollapsibleView(
        originRect: widget.originRect,
        card: widget.cardBuilder,
        cardRadius: widget.cardRadius,
        contentAlignment: Alignment.center,
        scrollController: _scroll,
        builder: (context, physics) => Scaffold(
          // 투명 — 축소 전환 중 뒤 화면이 비친다(CollapseRoute opaque:false).
          backgroundColor: Colors.transparent,
          // 웹(모바일 브라우저)에서는 키보드가 **본문 위로 덮게** 둔다.
          //
          // 이 화면은 뷰포트 높이 한 장짜리 에디터라, 본문을 키보드만큼 줄이면
          // 히어로·평점·입력칸이 한꺼번에 눌려 세로 비율이 눈에 띄게 무너진다.
          // 네이티브 앱은 지금 동작을 유지한다(기본값) — 이 작업 범위가 아니다.
          //
          // 브라우저가 레이아웃 뷰포트까지 줄이는 것은 여기서 못 막는다.
          // web/index.html 의 viewport `interactive-widget` 과 **짝**이어야
          // 실제로 안 줄어든다(한쪽만 고치면 다른 쪽이 그대로 줄인다).
          resizeToAvoidBottomInset: kIsWeb ? false : null,
          // 앱바 없음 — 투명 앱바를 두면 그 띠가 히어로 좌상단 첨부 버튼의
          // 탭을 가로채 버튼이 죽는다. 상단 버튼들은 히어로 안에 직접 얹는다.
          // 화면 = 전체화면 에디터 1장. 스크롤 본문은 없고, 뷰포트 높이짜리
          // 리스트로 CollapsibleView 의 '당겨서 축소' 드래그만 보존한다.
          //
          // 높이는 MediaQuery(창 크기)가 아니라 **실제 본문 제약**에서 받는다 —
          // 웹 셸(AppShell)이 본문을 가운데 컬럼·SafeArea 안으로 밀어넣고,
          // 키보드가 뜨면 Scaffold 가 본문을 줄이므로 창 크기와 어긋난다.
          body: LayoutBuilder(
            builder: (context, box) => ListView(
              controller: _scroll,
              physics: physics,
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: math.max(box.maxHeight, 420),
                  child: _editorHero(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 게시(수정) — 앱바 자리의 알약 버튼. 화면에서 유일한 상단 크롬이다.
  Widget _submitPill(bool editing) {
    return Pressable(
      scaleTo: 0.92,
      borderRadius: BorderRadius.circular(100),
      onTap: _submitting ? null : _submit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: _submitting
              ? const Color(0x59000000)
              : context.colors.primaryDark,
          borderRadius: BorderRadius.circular(100),
        ),
        child: _submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                editing ? '수정' : '등록',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  // ── 편집형 전체화면 에디터 — 후기 상세·게시글 작성과 동일한 시각 문법:
  //    미디어(사진/영상 포스터/블롭)가 화면을 채우고 하단 오버레이 패널에 정보.
  //    다른 점은 그 정보가 전부 **입력 가능**하다는 것뿐이다.
  //    (레이아웃을 바꿀 땐 widgets/review_cards.dart·post_media_hero.dart 와 맞출 것)
  Widget _editorHero() {
    final photoUrl = _photos.isNotEmpty ? _photos.first : null;
    // 비로그인 초안 사진은 아직 URL 이 없다 — 바이트로 그린다.
    final pending = photoUrl == null && _pending.isNotEmpty
        ? _pending.first
        : null;
    final videoOnly = photoUrl == null && pending == null && _videos.isNotEmpty;
    final posterUrl = videoOnly ? _videos.first.thumbUrl : null;
    final hasMedia = photoUrl != null || pending != null || videoOnly;
    final topPad = MediaQuery.paddingOf(context).top;
    final busy = _uploading || _uploadingVideo;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            // 배경 — 대표 사진(영상만이면 포스터), 없으면 블롭(시설마다 고정 패턴).
            if (photoUrl != null)
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                cacheWidth: 1200,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: context.colors.surfaceMuted),
              )
            else if (pending != null)
              Image.memory(pending.bytes, fit: BoxFit.cover)
            else if (videoOnly)
              posterUrl == null
                  ? const ColoredBox(color: Color(0xFF2B2B2B))
                  : Image.network(
                      posterUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 1200,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF2B2B2B)),
                    )
            else
              BlobBackground(
                seed: 'facility_review/${widget.facility.id}',
                color: context.colors.primary,
              ),
            // 사진 없는 후기 — 본문이 곧 히어로다(그 자리에서 그대로 쓴다).
            if (!hasMedia)
              Positioned(
                top: topPad + 56,
                left: 22,
                right: 22,
                bottom: h * 0.42,
                child: Center(child: _contentField(hero: true)),
              ),
            // 영상만 첨부 — 중앙 ▶ 배지(후기 카드와 동일 문법).
            if (videoOnly) const Center(child: VideoPlayBadge(size: 56)),
            // 하단 오버레이 패널 — 상세와 동일(뒤에만 점진 블러 + 스크림).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MediaOverlayPanel(
                blurSource: photoUrl == null
                    ? null
                    : Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                blurSourceSize: Size(w, h),
                bottomClearance: MediaQuery.paddingOf(context).bottom + 10,
                clearanceDuration: const Duration(milliseconds: 200),
                child: _overlayEditor(hasMedia: hasMedia),
              ),
            ),
            // 좌상단 — 첨부 추가 / 대표 첨부 제거.
            Positioned(
              top: topPad + 8,
              left: 12,
              child: Row(
                children: [
                  _cardIconButton(
                    icon: hasMedia
                        ? Icons.add_photo_alternate_outlined
                        : Icons.add_a_photo_outlined,
                    tooltip: '사진·동영상 첨부',
                    busy: busy,
                    onTap: _chooseAttachment,
                  ),
                  if (hasMedia && !busy) ...[
                    const SizedBox(width: 8),
                    _cardIconButton(
                      icon: Icons.close,
                      tooltip: '대표 첨부 제거',
                      onTap: _removeLeadMedia,
                    ),
                  ],
                ],
              ),
            ),
            // 우상단 — 게시(수정) / 삭제. 앱바 대신 히어로에 직접 얹는다.
            // 확장 전환이 안착한 뒤 나타난다(모프 중간에 불쑥 뜨지 않게).
            Positioned(
              top: topPad + 8,
              right: 12,
              child: CollapseSettledFade(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.existing != null)
                      // 게시 중에는 삭제를 막는다(중복 요청 방지).
                      IgnorePointer(
                        ignoring: _submitting,
                        child: OverlayIconButton(
                          icon: Icons.delete_outline,
                          tooltip: '후기 삭제',
                          color: const Color(0xFFFF8A80),
                          onPressed: _delete,
                        ),
                      ),
                    const SizedBox(width: 4),
                    _submitPill(widget.existing != null),
                  ],
                ),
              ),
            ),
            // 업체 혜택 배지 — 실제 후기 카드에 붙는 코너 배지의 미리보기.
            if (_hasIncentive)
              Positioned(
                top: topPad + 60,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: hasMedia
                        ? const Color(0x66000000)
                        : context.colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '업체 혜택',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: hasMedia
                          ? Colors.white
                          : context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 하단 오버레이의 입력 묶음 — 후기 카드의 정보 배치를 그대로 따르되
  /// 별점·본문·혜택 표시·첨부를 그 자리에서 편집한다.
  Widget _overlayEditor({required bool hasMedia}) {
    final me = SessionManager.instance.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 별점 — 카드 위에서 바로 매긴다(선택 시 살짝 튀는 촉감).
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Pressable(
                  scaleTo: 0.85,
                  borderRadius: BorderRadius.circular(100),
                  onTap: () => setState(() => _rating = i),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 30,
                      color: i <= _rating
                          ? const Color(0xFFFFB300)
                          : const Color(0x99FFFFFF),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                '$_rating',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              const Text(
                '방금 전',
                style: TextStyle(fontSize: 12, color: Color(0xCCFFFFFF)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.facility.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          // 사진 있는 후기의 본문 — 카드의 미리보기 자리에서 그대로 입력.
          // (사진이 없으면 본문은 화면 중앙 히어로가 맡는다.)
          if (hasMedia) ...[
            const SizedBox(height: 4),
            _contentField(hero: false),
          ],
          const SizedBox(height: 10),
          // 표시광고법: 대가성 후기는 경제적 이해관계 표시 의무 — 켜면 후기
          // 카드·상세·공유 뷰어에 '업체 혜택' 배지가 붙는다(카드 우상단 미리보기).
          _incentivePill(),
          const SizedBox(height: 12),
          // 후기 카드의 평점·작성자 줄 — 그 자리에서 첨부를 관리한다.
          Row(
            children: [
              Text(
                me?.nickname ?? '나',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xE6FFFFFF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _attachmentStrip()),
            ],
          ),
        ],
      ),
    );
  }

  /// 본문 입력 — 사진 없는 후기는 화면 중앙 히어로(후기 카드의 본문 자리),
  /// 사진 후기는 시설명 아래 미리보기 자리에서 그대로 입력한다.
  Widget _contentField({required bool hero}) {
    return TextField(
      controller: _contentCtrl,
      onChanged: (_) => setState(() {}),
      minLines: 1,
      maxLines: hero ? 9 : 3,
      maxLength: 1000,
      textAlign: hero ? TextAlign.center : TextAlign.start,
      cursorColor: hero ? context.colors.textPrimary : Colors.white,
      style: hero
          ? TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              height: 1.6,
            )
          : const TextStyle(
              fontSize: 13,
              color: Color(0xE0FFFFFF),
              height: 1.5,
            ),
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        counterText: '', // 글자수 카운터는 몰입형 오버레이에 어울리지 않는다
        hintText: '방문 후기를 남겨주세요',
        hintStyle: hero
            ? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textTertiary,
                height: 1.6,
              )
            : const TextStyle(
                fontSize: 13,
                color: Color(0x99FFFFFF),
                height: 1.5,
              ),
      ),
    );
  }

  /// 업체 혜택(할인·사은품) 수령 표시 토글 — 켜면 카드 우상단에 배지가 뜬다.
  Widget _incentivePill() {
    final on = _hasIncentive;
    return Pressable(
      scaleTo: 0.94,
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _hasIncentive = !on),
      child: AnimatedContainer(
        duration: MotionDurations.base,
        curve: SpringCurve.standard,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on
              ? context.colors.primaryDark
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.check_circle : Icons.card_giftcard_outlined,
              size: 13,
              color: on ? Colors.white : context.colors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '업체 혜택 받고 작성',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: on ? Colors.white : context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 첨부 관리 — 후기 카드의 통계 자리에서 사진·동영상을 훑어 보고 지운다.
  /// 첫 번째 항목이 카드 배경(대표)이 된다. 추가는 좌상단 버튼 한 곳에서만
  /// (여기 '+' 칩과 둘로 나뉘어 있으면 같은 동작의 입구가 중복된다).
  Widget _attachmentStrip() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < _photos.length; i++)
            _stripThumb(
              child: Image.network(
                _photos[i],
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                cacheWidth: 200,
              ),
              onRemove: () => setState(() => _photos.removeAt(i)),
            ),
          // 아직 업로드 전인 사진(비로그인) — 게시 때 함께 올라간다.
          for (var i = 0; i < _pending.length; i++)
            _stripThumb(
              child: Image.memory(
                _pending[i].bytes,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
              onRemove: () => setState(() => _pending.removeAt(i)),
            ),
          for (var i = 0; i < _videos.length; i++)
            _stripThumb(
              child: SizedBox(
                width: 40,
                height: 40,
                child: VideoPosterTile(
                  videoUrl: _videos[i].url,
                  posterUrl: _videos[i].thumbUrl,
                  borderRadius: BorderRadius.circular(10),
                  badgeSize: 18,
                  cacheWidth: 200,
                ),
              ),
              onRemove: () => setState(() => _videos.removeAt(i)),
            ),
        ],
      ),
    );
  }

  /// 첨부 스트립의 썸네일 한 칸(+ 제거 배지).
  Widget _stripThumb({required Widget child, required VoidCallback onRemove}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
            Positioned(
              right: -4,
              top: -4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xCC000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 대표(첫) 첨부 제거 — 카드 좌상단 × 버튼.
  void _removeLeadMedia() {
    setState(() {
      if (_photos.isNotEmpty) {
        _photos.removeAt(0);
      } else if (_pending.isNotEmpty) {
        _pending.removeAt(0);
      } else if (_videos.isNotEmpty) {
        _videos.removeAt(0);
      }
    });
  }

  /// 카드 위 원형 아이콘 버튼(좌상단 첨부 컨트롤) — 사진 위 가독용 프로스트.
  Widget _cardIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0x66000000),
            shape: BoxShape.circle,
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
