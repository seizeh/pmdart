import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../models/community.dart';
import '../motion/motion.dart';
import '../services/community/post_write_repository.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import '../utils/labels.dart' show categoryLabel;
import '../widgets/blob_background.dart';
import '../widgets/media_widgets.dart' show VideoPlayBadge, openVideoPlayer;
import '../widgets/post_editor_parts.dart';
import '../widgets/post_media_hero.dart' show MediaOverlayPanel;
import '../widgets/role_badge.dart' show categoryColor;
import 'image_crop_screen.dart';

/// 내 게시글 수정 — 제목·내용, 일정 게시글이면 약속 일정, 자유/입양이면 사진까지 편집.
/// 카메라 인증 게시글의 검증 사진·카테고리·연결 반려동물은 재검증이 필요해 바꿀 수 없다.
/// 저장 성공 시 pop(true).
class PostEditScreen extends StatefulWidget {
  final Post post;
  const PostEditScreen({super.key, required this.post});

  @override
  State<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends State<PostEditScreen> {
  final _write = PostWriteRepository.instance;
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.post.title,
  );
  late final TextEditingController _contentCtrl = TextEditingController(
    text: widget.post.content,
  );
  late DateTime? _scheduledAt = widget.post.scheduledAt;
  bool _saving = false;
  bool _deleting = false;

  /// 약속이 완료된 게시글은 수정할 수 없다 — 성사된 거래의 조건을 사후에 바꾸면
  /// 그걸 근거로 남은 후기·신뢰도가 흔들린다. 서버(`update_my_post`)가 정본이고
  /// 여기서는 이유를 미리 알려주고 저장 버튼을 잠근다.
  ///
  /// **삭제는 막지 않는다** — 자기 글을 내리는 건 별개 권리이고, 이 화면이 삭제의
  /// 유일한 진입점이라 함께 잠그면 내릴 방법이 사라진다.
  bool _editLocked = false;
  bool _lockChecked = false;

  // 미디어 편집(자유/입양/소식만). null=미디어 없음. 변경 시 _imageEdited=true.
  // 영상 게시글이면 표시용 URL 은 포스터(썸네일)다.
  late String? _imageUrl = widget.post.isVideo
      ? widget.post.imageThumbUrl
      : widget.post.imageUrl;
  late bool _isVideo = widget.post.isVideo; // 현재 미디어가 영상인지
  UploadedImage? _newImage; // 새로 올린 사진(있으면 저장 시 이 값 사용)
  UploadedVideo? _newVideo; // 새로 올린 동영상(사진과 상호 배타)
  bool _imageEdited = false; // 사용자가 미디어를 바꾸거나 지웠는지
  bool _uploading = false;

  /// 미리보기로 재생할 영상 URL — 새로 올린 것이 있으면 그쪽, 없으면 원래 영상.
  /// (`_imageUrl` 은 영상일 때 **포스터** 주소라 재생에 쓸 수 없다.)
  String? get _videoUrl =>
      _newVideo?.url ?? (widget.post.isVideo ? widget.post.imageUrl : null);

  // 원래 약속 일정이 있던 게시글만 일정 편집 노출(카테고리는 못 바꾸므로 유형 고정).
  bool get _hasSchedule => widget.post.scheduledAt != null;

  // 자유/입양/소식 게시글만 미디어 편집 허용(카메라 인증 게시글은 검증 사진 고정).
  bool get _canEditImage =>
      ['free', 'adoption', 'news'].contains(widget.post.category);

  // 영상은 자유/소식만(서버 CHECK 동일 — 입양은 사진만).
  bool get _canEditVideo =>
      widget.post.category == 'free' || widget.post.category == 'news';

  bool get _canSave =>
      !_uploading &&
      !_editLocked &&
      _titleCtrl.text.trim().isNotEmpty &&
      _contentCtrl.text.trim().isNotEmpty &&
      (!_hasSchedule || _scheduledAt != null);

  @override
  void initState() {
    super.initState();
    unawaited(_checkEditLock());
  }

  /// 저장하지 않은 변경이 있는가 — 닫기 전 확인 여부 판단용.
  bool get _dirty =>
      _titleCtrl.text != widget.post.title ||
      _contentCtrl.text != widget.post.content ||
      _scheduledAt != widget.post.scheduledAt ||
      _imageEdited;

  /// 닫기 — 고친 게 있으면 버릴지 먼저 묻는다(잠긴 글은 고칠 수 없어 바로 닫힌다).
  Future<void> _close() async {
    if (_saving || _deleting) return;
    if (!_dirty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('수정을 취소할까요?'),
        content: const Text('저장하지 않은 변경 내용은 사라져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 수정'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('취소', style: TextStyle(color: ctx.colors.danger)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  /// 자유·입양은 애초에 약속이 생기지 않으므로 조회를 건너뛴다(0012).
  Future<void> _checkEditLock() async {
    if (_canEditImage && !_hasSchedule) {
      setState(() => _lockChecked = true);
      return;
    }
    final locked = await _write.postEditLocked(widget.post.id);
    if (!mounted) return;
    setState(() {
      _editLocked = locked;
      _lockChecked = true;
    });
  }

  /// 미디어 추가/교체 진입 — 자유/소식은 사진/동영상 선택, 입양은 사진만.
  Future<void> _pickMedia() async {
    if (!_canEditVideo) return _pickImage();
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
              leading: Icon(
                Icons.photo_library_outlined,
                color: context.colors.primaryDark,
              ),
              title: const Text('사진'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: Icon(
                Icons.videocam_outlined,
                color: context.colors.primaryDark,
              ),
              title: const Text('동영상'),
              subtitle: const Text('최대 60초 · 100MB'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (src == 'photo') return _pickImage();
    if (src == 'video') return _pickVideo();
  }

  /// 동영상 선택 → 업로드(포스터 생성 포함). 100MB 초과는 업로드 전에 안내.
  Future<void> _pickVideo() async {
    final file = await StorageService.instance.pickVideo();
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final up = await StorageService.instance.uploadVideo(
        file,
        category: 'posts',
      );
      if (!mounted) return;
      setState(() {
        _newVideo = up;
        _newImage = null;
        _imageUrl = up.thumbUrl;
        _isVideo = true;
        _imageEdited = true;
        _uploading = false;
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message), // 100MB 초과 등 한국어 안내
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('동영상 업로드에 실패했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 갤러리 선택 → 표시비율 크롭 → 업로드(자유/입양은 촬영 검증 없음).
  Future<void> _pickImage() async {
    final file = await StorageService.instance.pickImage();
    if (file == null) return;
    final raw = await file.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.push<CroppedImage>(
      context,
      AppPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(bytes: raw),
      ),
    );
    // 크롭 화면 대기 중 강제 라우팅으로 라우트가 걷힐 수 있다 — _pickVideo 와
    // 동일한 가드(#238, 이 비대칭이 원 발견 지점이었다).
    if (cropped == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final up = await StorageService.instance.uploadBytes(
        cropped.bytes,
        category: 'posts',
        ext: cropped.ext,
        mime: cropped.mime,
      );
      if (!mounted) return;
      setState(() {
        _newImage = up;
        _newVideo = null;
        _imageUrl = up.url;
        _isVideo = false;
        _imageEdited = true;
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('사진 업로드에 실패했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _newImage = null;
      _newVideo = null;
      _imageUrl = null;
      _isVideo = false;
      _imageEdited = true;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final base = _scheduledAt ?? DateTime.now().add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      initialDate: base.isBefore(DateTime.now()) ? DateTime.now() : base,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      // 원형 다이얼 대신 숫자 입력식 — 시간은 키패드로 바로 입력한다.
      initialEntryMode: TimePickerEntryMode.inputOnly,
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      await _write.updatePost(
        widget.post.id,
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        scheduledAt: _hasSchedule ? _scheduledAt : null,
        editImage: _canEditImage && _imageEdited,
        // 영상 교체 시 단일 미디어 슬롯에 영상 URL/MIME/크기 + 포스터 전달.
        // 제거 시 null → 서버가 미디어 제거.
        image: _newVideo != null
            ? UploadedImage(
                url: _newVideo!.url,
                mime: _newVideo!.mime,
                size: _newVideo!.size,
              )
            : _newImage,
        imageThumbUrl: _newVideo?.thumbUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('게시글을 수정했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('수정에 실패했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 삭제(소프트) — 확인 후 delete_my_post. 성공 시 pop(true) → 상세가 재조회로 닫힌다.
  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('이 게시글을 삭제할까요? 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: TextButton.styleFrom(foregroundColor: context.colors.danger),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _write.deletePost(widget.post.id);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('게시글을 삭제했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('삭제에 실패했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 작성 화면(post_create_screen)과 같은 히어로 에디터 — 대표 미디어가 배경이
    // 되고, 하단 오버레이 패널 안에서 제목·본문·일정을 그 자리에서 고친다.
    // 조각은 widgets/post_editor_parts.dart 공용(둘이 갈라지지 않게).
    //
    // 작성 화면과 다른 점은 '무엇을 못 고치는가'뿐이다: 카테고리·연결 펫은 고정,
    // 미디어는 자유/입양/소식만, 일정은 원래 있던 글만, 그리고 약속이 완료됐으면
    // 전부 잠긴다(_editLocked).
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      // 시스템 뒤로가기(안드로이드 버튼·iOS 스와이프)도 닫기 버튼과 같은 확인을
      // 거치게 한다 — 한쪽만 막으면 다른 쪽으로 변경이 조용히 사라진다.
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_close());
        },
        child: Scaffold(
          backgroundColor: context.colors.background,
          body: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: math.max(box.maxHeight, 420),
                child: _editorHero(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editorHero() {
    final color = categoryColor(context, widget.post.category);
    final photoUrl = _imageUrl;
    final hasPhoto = photoUrl != null;
    final topPad = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            if (photoUrl != null)
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                cacheWidth: 1200,
                errorBuilder: (_, _, _) => _isVideo
                    ? const ColoredBox(color: Color(0xFF2B2B2B))
                    : BlobBackground(
                        seed: 'preview/${widget.post.category}',
                        color: color,
                      ),
              )
            else
              BlobBackground(
                seed: 'preview/${widget.post.category}',
                color: color,
              ),
            // 사진 없는 글 — 본문이 곧 히어로다(작성 화면과 같은 자리).
            if (!hasPhoto)
              Positioned(
                top: topPad + 56,
                left: 22,
                right: 22,
                bottom: h * 0.42,
                child: Center(
                  child: EditorContentField(
                    controller: _contentCtrl,
                    hero: true,
                    onChanged: _editLocked ? null : (_) => setState(() {}),
                  ),
                ),
              ),
            // 탭하면 미리보기. 새로 올린 영상이 있으면 그쪽, 없으면 원래 영상.
            // ⚠️ VideoPlayBadge 는 장식일 뿐이라 감싸지 않으면 눌러도 무반응이다.
            if (_isVideo && _videoUrl != null)
              Center(
                child: Pressable(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => openVideoPlayer(context, _videoUrl!),
                  child: const VideoPlayBadge(size: 56),
                ),
              ),
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
                child: _overlayEditor(hasPhoto: hasPhoto, color: color),
              ),
            ),
            // 좌상단 — 닫기 + (편집 가능하면) 미디어 교체/제거.
            //
            // ⚠️ 닫기는 **조건 없이 항상** 있어야 한다. 작성 화면은 CollapseRoute 로
            // 열려 아래로 쓸어내리면 닫히지만, 이 화면은 일반 push 라 그 제스처가
            // 없다. 앱바를 없애면서 닫기까지 사라져, 수정이 잠긴 게시글에 들어가면
            // 웹에서 빠져나올 방법이 없었다(실사용 신고).
            Positioned(
              top: topPad + 8,
              left: 12,
              child: Row(
                children: [
                  EditorCardIconButton(
                    icon: Icons.arrow_back,
                    tooltip: '닫기',
                    onTap: _close,
                  ),
                  if (_canEditImage && !_editLocked) ...[
                    const SizedBox(width: 8),
                    EditorCardIconButton(
                      icon: hasPhoto
                          ? Icons.photo_camera_outlined
                          : Icons.add_a_photo_outlined,
                      tooltip: _canEditVideo ? '사진·동영상 교체' : '사진 교체',
                      busy: _uploading,
                      onTap: _pickMedia,
                    ),
                    if (hasPhoto && !_uploading) ...[
                      const SizedBox(width: 8),
                      EditorCardIconButton(
                        icon: Icons.close,
                        tooltip: '사진 제거',
                        onTap: _removeImage,
                      ),
                    ],
                  ],
                ],
              ),
            ),
            // 우상단 — 삭제 + 저장. 삭제는 잠겨도 남는다(이 화면이 유일한 진입점).
            Positioned(
              top: topPad + 8,
              right: 12,
              child: CollapseSettledFade(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EditorCardIconButton(
                      icon: Icons.delete_outline,
                      tooltip: '게시글 삭제',
                      busy: _deleting,
                      onTap: (_saving || _deleting) ? () {} : _confirmDelete,
                    ),
                    const SizedBox(width: 8),
                    EditorSubmitPill(
                      label: '저장',
                      enabled: _canSave && !_saving && !_deleting,
                      busy: _saving,
                      onTap: _save,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 하단 오버레이의 입력 묶음 — 작성 화면의 배치를 그대로 따르되 고정 필드는
  /// 편집 힌트(▾) 없이 표시만 한다.
  Widget _overlayEditor({required bool hasPhoto, required Color color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 약속 완료 → 수정 잠김. 저장이 왜 안 되는지 여기서 먼저 말한다.
          if (_lockChecked && _editLocked) ...[
            _LockedNotice(),
            const SizedBox(height: 10),
          ],
          // 카테고리 — 수정 불가라 ▾ 없이 표시만.
          EditorCategoryPill(
            text: categoryLabel(widget.post.category),
            textColor: color,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            maxLines: 1,
            enabled: !_editLocked,
            onChanged: (_) => setState(() {}),
            cursorColor: Colors.white,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            decoration: const InputDecoration(
              isDense: true,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              hintText: '제목을 입력하세요',
              hintStyle: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0x99FFFFFF),
              ),
            ),
          ),
          if (hasPhoto) ...[
            const SizedBox(height: 4),
            EditorContentField(
              controller: _contentCtrl,
              hero: false,
              onChanged: _editLocked ? null : (_) => setState(() {}),
            ),
          ],
          if (_hasSchedule) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _editLocked ? null : _pickDateTime,
              child: EditorMetaPill(
                icon: Icons.event_outlined,
                label: _scheduledAt == null
                    ? '약속 일정 선택 (필수)'
                    : '${_scheduledAt!.month}/${_scheduledAt!.day} ${_scheduledAt!.hour}시',
                editable: !_editLocked,
              ),
            ),
            if (!_editLocked) ...[
              const SizedBox(height: 6),
              const Text(
                '일정을 바꾸면 지원한 사용자에게 변경 알림이 전송돼요',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Color(0xCCFFFFFF),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            _canEditImage
                ? '카테고리·연결한 반려동물은 수정할 수 없어요'
                : '사진·카테고리·연결한 반려동물은 수정할 수 없어요',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: Color(0xCCFFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

/// 약속 완료로 수정이 잠겼을 때의 안내 — 저장만 막고 삭제는 남는다는 것까지 말한다.
class _LockedNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: c.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '약속이 완료된 게시글이라 내용을 수정할 수 없어요.\n'
              '삭제는 계속 할 수 있어요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
