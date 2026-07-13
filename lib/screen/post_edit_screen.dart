import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show categoryLabel;
import '../models/community.dart';
import '../services/community_repository.dart';
import '../services/storage_service.dart';
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
  final _repo = CommunityRepository.instance;
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.post.title,
  );
  late final TextEditingController _contentCtrl = TextEditingController(
    text: widget.post.content,
  );
  late DateTime? _scheduledAt = widget.post.scheduledAt;
  bool _saving = false;
  bool _deleting = false;

  // 사진 편집(자유/입양만). null=사진 없음. 변경 시 _imageEdited=true.
  late String? _imageUrl = widget.post.imageUrl;
  UploadedImage? _newImage; // 새로 올린 사진(있으면 저장 시 이 값 사용)
  bool _imageEdited = false; // 사용자가 사진을 바꾸거나 지웠는지
  bool _uploading = false;

  // 원래 약속 일정이 있던 게시글만 일정 편집 노출(카테고리는 못 바꾸므로 유형 고정).
  bool get _hasSchedule => widget.post.scheduledAt != null;

  // 자유/입양 게시글만 사진 편집 허용(카메라 인증 게시글은 검증 사진 고정).
  bool get _canEditImage =>
      widget.post.category == 'free' || widget.post.category == 'adoption';

  bool get _canSave =>
      !_uploading &&
      _titleCtrl.text.trim().isNotEmpty &&
      _contentCtrl.text.trim().isNotEmpty &&
      (!_hasSchedule || _scheduledAt != null);

  /// 갤러리 선택 → 표시비율 크롭 → 업로드(자유/입양은 촬영 검증 없음).
  Future<void> _pickImage() async {
    final file = await StorageService.instance.pickImage();
    if (file == null) return;
    final raw = await file.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.push<Uint8List>(
      context,
      AppPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(bytes: raw),
      ),
    );
    if (cropped == null) return;
    setState(() => _uploading = true);
    try {
      final up = await StorageService.instance.uploadBytes(
        cropped,
        category: 'posts',
        ext: 'png',
        mime: 'image/png',
      );
      if (!mounted) return;
      setState(() {
        _newImage = up;
        _imageUrl = up.url;
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
      _imageUrl = null;
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
      await _repo.updatePost(
        widget.post.id,
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        scheduledAt: _hasSchedule ? _scheduledAt : null,
        editImage: _canEditImage && _imageEdited,
        image: _newImage, // 제거 시 null → 서버가 사진 제거
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
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _repo.deletePost(widget.post.id);
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('게시글 수정'),
        actions: [
          // 삭제 — 저장 왼쪽. 진행 중엔 서로 비활성화.
          TextButton(
            onPressed: (_saving || _deleting) ? null : _confirmDelete,
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '삭제',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
          TextButton(
            onPressed: (_canSave && !_saving && !_deleting) ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '저장',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
              // 카테고리는 편집 불가 — 현재 값만 표시.
              const _SectionLabel('카테고리'),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(
                  categoryLabel(widget.post.category),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('제목'),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(hintText: '제목을 입력하세요'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('내용'),
              TextField(
                controller: _contentCtrl,
                maxLines: 8,
                decoration: const InputDecoration(hintText: '내용을 입력하세요'),
                onChanged: (_) => setState(() {}),
              ),
              if (_canEditImage) ...[
                const SizedBox(height: 20),
                const _SectionLabel('사진 (선택)'),
                _PhotoEditor(
                  url: _imageUrl,
                  uploading: _uploading,
                  onPick: _pickImage,
                  onRemove: _removeImage,
                ),
              ],
              if (_hasSchedule) ...[
                const SizedBox(height: 20),
                const _SectionLabel('약속 일정'),
                InkWell(
                  onTap: _pickDateTime,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event,
                          color: AppColors.primaryDark,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _scheduledAt == null
                              ? '일정을 선택하세요'
                              : '${_scheduledAt!.year}년 ${_scheduledAt!.month}월 ${_scheduledAt!.day}일 ${_scheduledAt!.hour}시',
                          style: TextStyle(
                            fontSize: 14,
                            color: _scheduledAt == null
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '일정을 바꾸면 이 게시글에 지원한 사용자에게 변경 알림이 전송돼요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '사진·카테고리·연결한 반려동물은 수정할 수 없어요. '
                '변경하려면 삭제 후 다시 작성해주세요.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 자유/입양 게시글 사진 편집기 — 갤러리 선택/미리보기/삭제(촬영 검증 없음).
class _PhotoEditor extends StatelessWidget {
  final String? url;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  const _PhotoEditor({
    required this.url,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (url == null) {
      return InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_a_photo_outlined,
                color: AppColors.primaryDark,
                size: 26,
              ),
              SizedBox(height: 6),
              Text(
                '사진 추가',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: kPostImageAspectRatio,
            child: Image.network(
              url!,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: AppColors.surfaceMuted,
                child: const Center(child: Icon(Icons.image, size: 40)),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
