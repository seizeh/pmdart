import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/community.dart';
import '../services/community_repository.dart';
import '../services/photo_verify_repository.dart';
import '../services/storage_service.dart';
import '../widgets/role_badge.dart';

/// 게시글 작성 — 카테고리 선택 / 제목·내용 / 약속 일정(선택) / 펫 연결.
/// 카테고리에 따라 입력 UI가 다르게 분기:
///  · walk_together / walk_proxy / care : 펫 다중 선택 + 약속 일정 필수
///  · give_away : 본인 owner 인 펫 1마리만 + 약속 일정 없음
///  · adoption / free : 펫 선택 없음
class PostCreateScreen extends StatefulWidget {
  const PostCreateScreen({super.key});

  @override
  State<PostCreateScreen> createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends State<PostCreateScreen> {
  final _repo = CommunityRepository.instance;

  String _category = 'walk_together';
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  DateTime? _scheduledAt;
  final Set<String> _selectedPetIds = {};

  List<MyPet> _pets = [];
  bool _loadingPets = true;
  bool _submitting = false;

  UploadedImage? _uploadedImage;
  bool _uploadingImage = false;
  // 사진 필수 카테고리(walk/care/give_away)에서 서버 검증 통과 시 받는 1회용 토큰.
  String? _photoToken;
  // 검증 사진이 묶인(촬영한) 펫 id — 이 펫이 선택 해제되면 사진을 무효화한다.
  String? _photoPetId;

  static const _categories = [
    'walk_together',
    'walk_proxy',
    'care',
    'give_away',
    'adoption',
    'free',
  ];

  bool get _needsSchedule =>
      ['walk_together', 'walk_proxy', 'care'].contains(_category);
  bool get _allowsSchedule => _needsSchedule || _category == 'free';
  bool get _needsPet =>
      ['walk_together', 'walk_proxy', 'care', 'give_away'].contains(_category);
  bool get _giveAway => _category == 'give_away';
  // 자유게시글(free)·입양게시글(adoption)을 제외한 게시글은 사진 등록이 필수.
  bool get _needsPhoto => !['free', 'adoption'].contains(_category);

  @override
  void initState() {
    super.initState();
    _loadPets();
  }

  Future<void> _loadPets() async {
    try {
      final pets = await _repo.fetchMyPets();
      if (!mounted) return;
      setState(() {
        _pets = pets;
        _loadingPets = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPets = false);
    }
  }

  /// 사진 영역 탭. 사진 필수 카테고리는 카메라 촬영→서버 검증, 그 외는 갤러리 업로드.
  Future<void> _onPhotoTap() =>
      _needsPhoto ? _captureAndVerify() : _pickFromGallery();

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// 사진 필수 카테고리(walk/care/give_away): 촬영 대상 펫 결정 → 카메라 촬영 →
  /// 위치·AI 실존 + 등록 펫 개체 대조. 통과 시 서버 URL/토큰 보관.
  Future<void> _captureAndVerify() async {
    // 1) 촬영 대상 펫 결정(연결한 펫 중에서)
    final candidates =
        _pets.where((p) => _selectedPetIds.contains(p.id)).toList();
    if (candidates.isEmpty) {
      _toast('먼저 연결할 반려동물을 선택해주세요');
      return;
    }
    final target = candidates.length == 1
        ? candidates.first
        : await _choosePhotoPet(candidates);
    if (target == null) return; // 선택 취소

    // 2) 기준(AI 인증용) 사진이 없으면 먼저 등록 유도
    if (!target.hasAiReference) {
      await _promptRegisterReference(target);
      return;
    }

    // 3) 촬영 → 검증(개체 대조 포함)
    final shot = await StorageService.instance.capturePostPhoto();
    if (shot == null) return;
    setState(() {
      _uploadedImage = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = true;
    });
    final res = await PhotoVerifyRepository.instance
        .verifyPostPhoto(shot, petId: target.id);
    if (!mounted) return;
    if (res.pass && res.imageUrl != null && res.token != null) {
      setState(() {
        _uploadedImage = UploadedImage(
          url: res.imageUrl!,
          mime: shot.mimeType ?? 'image/jpeg',
          size: 0,
        );
        _photoToken = res.token;
        _photoPetId = target.id;
        _uploadingImage = false;
      });
      if (!res.matched) {
        _toast('등록된 반려동물과 일치 여부가 불확실해요. 게시는 되지만 검수 대상이 될 수 있어요');
      }
    } else {
      setState(() => _uploadingImage = false);
      _toast(res.message);
    }
  }

  /// 여러 마리를 연결한 경우, 사진 속 반려동물을 고른다.
  Future<MyPet?> _choosePhotoPet(List<MyPet> candidates) {
    return showModalBottomSheet<MyPet>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('사진 속 반려동물을 선택하세요',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            ...candidates.map((p) => ListTile(
                  title: Text('${p.name}  ·  ${p.species}'),
                  subtitle: p.hasAiReference
                      ? null
                      : const Text('인증용 사진 필요',
                          style: TextStyle(color: AppColors.warning, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, p),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 기준 사진이 없는 펫: 소유자면 지금 촬영해 등록, 아니면 안내만.
  Future<void> _promptRegisterReference(MyPet target) async {
    if (target.role != 'owner') {
      _toast('${target.name}의 인증용 사진은 소유자가 먼저 등록해야 해요');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('인증용 사진 등록'),
        content: Text('${target.name}의 AI 인증용 사진이 아직 없어요.\n'
            '지금 ${target.name}를 카메라로 촬영해 등록할까요?\n'
            '(이후 게시글 사진이 이 사진과 대조됩니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('촬영')),
        ],
      ),
    );
    if (ok != true) return;

    final shot = await StorageService.instance.capturePostPhoto();
    if (shot == null) return;
    setState(() => _uploadingImage = true);
    final res = await PhotoVerifyRepository.instance
        .verifyPetReference(shot, petId: target.id);
    if (!mounted) return;
    setState(() => _uploadingImage = false);
    if (res.pass) {
      _toast('${target.name}의 인증용 사진을 등록했어요. 이제 게시글 사진을 촬영하세요');
      await _loadPets(); // hasAiReference 갱신
    } else {
      _toast(res.message);
    }
  }

  /// free/adoption: 기존 갤러리 선택 → 업로드(검증 없음).
  Future<void> _pickFromGallery() async {
    final file = await StorageService.instance.pickImage();
    if (file == null) return;
    setState(() {
      _uploadedImage = null;
      _photoToken = null;
      _uploadingImage = true;
    });
    try {
      final up = await StorageService.instance.upload(file, category: 'posts');
      if (!mounted) return;
      setState(() {
        _uploadedImage = up;
        _uploadingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
      });
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
      _uploadedImage = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('새 게시글'),
        actions: [
          TextButton(
            onPressed: (_canSubmit && !_submitting) ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '등록',
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
              const _SectionLabel('카테고리'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories
                    .map((c) => CategoryChip(
                  category: c,
                  selected: _category == c,
                  onTap: () => setState(() {
                    _category = c;
                    _selectedPetIds.clear();
                    if (!_allowsSchedule) _scheduledAt = null;
                    // 카테고리가 바뀌면 사진 입력 경로(카메라/갤러리)가 달라지므로 초기화.
                    _uploadedImage = null;
                    _photoToken = null;
                    _photoPetId = null;
                    _uploadingImage = false;
                  }),
                ))
                    .toList(),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('제목'),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  hintText: '예) 동탄2동 산책 메이트 구해요',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('내용'),
              TextField(
                controller: _contentCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '자세한 내용을 적어주세요',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              _SectionLabel(_needsPhoto ? '사진 (촬영 인증)' : '사진 (선택)'),
              if (_needsPhoto)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '아래에서 반려동물을 먼저 선택한 뒤, 그 아이를 카메라로 촬영하세요. '
                    '등록된 인증 사진과 대조해 실제 반려동물인지 확인합니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
              _PhotoPicker(
                url: _uploadedImage?.url,
                uploading: _uploadingImage,
                requireCamera: _needsPhoto,
                onPick: _onPhotoTap,
                onRemove: _removeImage,
              ),
              if (_allowsSchedule) ...[
                const SizedBox(height: 20),
                _SectionLabel(_needsSchedule ? '약속 일정' : '약속 일정 (선택)'),
                InkWell(
                  onTap: _pickDateTime,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event,
                            color: AppColors.primaryDark, size: 20),
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
              ],
              if (_needsPet) ...[
                const SizedBox(height: 20),
                _SectionLabel(_giveAway ? '분양할 반려동물 (소유자만, 1마리)' : '연결할 반려동물'),
                if (_loadingPets)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_pets.where((p) => !_giveAway || p.role == 'owner').isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _giveAway
                          ? '분양은 본인이 소유자인 반려동물이 있어야 작성할 수 있어요'
                          : '연결할 반려동물이 없어요. 먼저 반려동물을 등록해주세요',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                    ),
                  ),
                ..._pets.where((p) {
                  if (_giveAway) return p.role == 'owner';
                  return true;
                }).map((p) {
                  final selected = _selectedPetIds.contains(p.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() {
                        if (_giveAway) {
                          _selectedPetIds
                            ..clear()
                            ..add(p.id);
                        } else {
                          if (selected) {
                            _selectedPetIds.remove(p.id);
                          } else {
                            _selectedPetIds.add(p.id);
                          }
                        }
                        // 검증 사진이 묶인 펫이 선택 해제되면 사진을 무효화한다.
                        if (_photoPetId != null &&
                            !_selectedPetIds.contains(_photoPetId)) {
                          _uploadedImage = null;
                          _photoToken = null;
                          _photoPetId = null;
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primarySoft.withValues(alpha: 0.3)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : AppColors.border,
                            width: selected ? 1.5 : 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_off,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${p.name}  ·  ${p.species}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            RoleBadge(role: p.role, compact: true),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                if (_giveAway)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '분양이 완료되면 소유권이 자동으로 입양자에게 이전됩니다.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSubmit {
    if (_uploadingImage) return false;
    if (_titleCtrl.text.isEmpty || _contentCtrl.text.isEmpty) return false;
    if (_needsPhoto && (_uploadedImage == null || _photoToken == null)) {
      return false;
    }
    if (_needsSchedule && _scheduledAt == null) return false;
    if (_needsPet && _selectedPetIds.isEmpty) return false;
    return true;
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await _repo.createPost(
        category: _category,
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        scheduledAt: _allowsSchedule ? _scheduledAt : null,
        petIds: _needsPet ? _selectedPetIds.toList() : const [],
        imageUrl: _uploadedImage?.url,
        imageMime: _uploadedImage?.mime,
        imageSize: _uploadedImage?.size,
        photoToken: _needsPhoto ? _photoToken : null,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('게시글을 등록했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// posts 검증 트리거의 한글 메시지를 사용자에게 그대로 노출.
  String _friendlyError(Object e) {
    final s = e.toString();
    final idx = s.indexOf('posts:');
    if (idx >= 0) {
      return s.substring(idx).split('\n').first.replaceFirst('posts:', '').trim();
    }
    return '게시글 등록에 실패했어요';
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

/// 사진 선택/미리보기. 선택 즉시 업로드되며 미리보기는 업로드된 URL 로 표시(크로스플랫폼).
class _PhotoPicker extends StatelessWidget {
  final String? url;
  final bool uploading;
  final bool requireCamera;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _PhotoPicker({
    required this.url,
    required this.uploading,
    required this.onRemove,
    required this.onPick,
    this.requireCamera = false,
  });

  @override
  Widget build(BuildContext context) {
    // 업로드/검증 중 — 스피너 박스
    if (uploading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (requireCamera) ...[
                const SizedBox(height: 12),
                const Text('사진을 인증하는 중이에요',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      );
    }
    // 미선택 — 추가/촬영 버튼
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  requireCamera
                      ? Icons.photo_camera_outlined
                      : Icons.add_a_photo_outlined,
                  color: AppColors.primaryDark,
                  size: 26),
              const SizedBox(height: 6),
              Text(requireCamera ? '사진 촬영' : '사진 추가',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    // 업로드 완료 — 미리보기 + 삭제 (가로 3 : 세로 4)
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: kPostImageAspectRatio, // 4284 : 5712
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