import 'dart:typed_data';
import '../motion/motion.dart';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/community.dart';
import '../models/profile.dart';
import '../services/community_repository.dart';
import '../services/photo_verify_repository.dart';
import '../services/profile_repository.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';
import '../widgets/role_badge.dart';
import 'image_crop_screen.dart';

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

  // 현재 위치가 인증 동네와 다를 때 경고 — 게시글은 인증 동네 기준으로 등록됨.
  String? _currentDong; // 지금 있는 동
  String? _verifiedDong; // 인증한 동
  bool get _regionMismatch =>
      _currentDong != null &&
      _verifiedDong != null &&
      _currentDong != _verifiedDong;

  @override
  void initState() {
    super.initState();
    _loadPets();
    _checkRegion();
  }

  /// 현재 위치 동 vs 인증 동 비교(베스트에포트). 위치 없으면 경고 안 함.
  Future<void> _checkRegion() async {
    try {
      final reg = await ProfileRepository.instance.fetchRegion();
      final verified = ProfileData.regionNameFromAddress(reg.address,
          verified: reg.verified);
      if (verified == null) return; // 미인증이면 비교 의미 없음
      final loc = await LocationService.instance.getCurrentPosition();
      if (loc.status != LocationStatus.ok || loc.position == null) return;
      final cur = await ProfileRepository.instance
          .regionNameAt(loc.position!.latitude, loc.position!.longitude);
      if (!mounted || cur == null) return;
      setState(() {
        _verifiedDong = verified;
        _currentDong = cur;
      });
    } catch (_) {/* 베스트에포트 — 실패 시 경고 없음 */}
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

    // 2) 신원 인증(영상)이 안 된 펫이면 안내(인증은 펫 등록/수정 화면에서 진행)
    if (!target.isIdentityVerified) {
      _toast('${target.name}의 신원 인증(영상)을 먼저 완료해주세요');
      return;
    }

    // 3) 촬영 → 검증(등록 펫과 동일개체 매칭)
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
                  subtitle: p.isIdentityVerified
                      ? null
                      : const Text('신원 인증 필요',
                          style: TextStyle(color: AppColors.warning, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, p),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// free/adoption: 갤러리 선택 → 표시 비율(3:4)에 맞게 영역 조정(크롭) → 업로드(검증 없음).
  Future<void> _pickFromGallery() async {
    final file = await StorageService.instance.pickImage();
    if (file == null) return;
    final raw = await file.readAsBytes();
    if (!mounted) return;
    // 보여질 영역 조정 화면(취소하면 첨부 중단).
    final cropped = await Navigator.push<Uint8List>(
      context,
      AppPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(bytes: raw),
      ),
    );
    if (cropped == null) return;
    setState(() {
      _uploadedImage = null;
      _photoToken = null;
      _uploadingImage = true;
    });
    try {
      final up = await StorageService.instance
          .uploadBytes(cropped, category: 'posts', ext: 'png', mime: 'image/png');
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
              if (_regionMismatch) ...[
                _RegionWarning(current: _currentDong!, verified: _verifiedDong!),
                const SizedBox(height: 16),
              ],
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

/// 현재 위치가 인증 동네와 다를 때 경고 배너.
class _RegionWarning extends StatelessWidget {
  final String current;
  final String verified;
  const _RegionWarning({required this.current, required this.verified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '지금 계신 곳($current)이 인증 동네($verified)와 달라요.\n'
              '이 게시글은 인증 동네($verified) 기준으로 등록됩니다.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
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