import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show MockPet;
import '../services/pet_repository.dart';
import '../services/storage_service.dart';
import 'pet_identity_enroll_screen.dart';

/// 가입 단계 등에서 미리 받아온 펫 정보 초안 — 신규 등록 폼을 프리필한다.
class PetDraft {
  final String name;
  final String? speciesKind; // 'dog' | 'cat'
  final String species; // 품종(자유 입력)
  final String? gender;
  final DateTime? birthDate;

  /// 가입 화면에서 받아둔 공동보호자 전화번호 — 펫 등록(인증 완료) 시 자동 초대.
  final List<String> coGuardianPhones;

  const PetDraft({
    required this.name,
    this.speciesKind,
    this.species = '',
    this.gender,
    this.birthDate,
    this.coGuardianPhones = const [],
  });
}

/// 반려동물 등록/수정 화면. [pet] 가 있으면 수정, 없으면 신규 등록.
/// 신규 등록 시 [draft] 가 있으면 폼을 프리필한다(가입 흐름 연계).
class PetEditScreen extends StatefulWidget {
  final MockPet? pet;
  final PetDraft? draft;
  const PetEditScreen({super.key, this.pet, this.draft});

  @override
  State<PetEditScreen> createState() => _PetEditScreenState();
}

class _PetEditScreenState extends State<PetEditScreen> {
  final _nameCtrl = TextEditingController();
  final _speciesCtrl = TextEditingController(); // 품종(자유 입력)
  final _bioCtrl = TextEditingController();
  String? _speciesKind; // 'dog' | 'cat' (강아지/고양이) — 필수
  String? _gender;
  DateTime? _birthDate;
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;
  bool _identityVerified = false; // 신원 영상 인증 완료 여부 (0020)

  bool get _isEdit => widget.pet != null;
  bool get _isOwner => widget.pet?.role == 'owner';

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (widget.pet == null && d != null) {
      _nameCtrl.text = d.name;
      _speciesCtrl.text = d.species;
      _speciesKind = d.speciesKind;
      _gender = d.gender;
      _birthDate = d.birthDate;
    }
    final p = widget.pet;
    if (p != null) {
      _nameCtrl.text = p.name;
      _speciesCtrl.text = p.species;
      _speciesKind = p.speciesKind;
      _bioCtrl.text = p.bio ?? '';
      _gender = p.gender;
      _birthDate = p.birthDate;
      _imageUrl = p.imageUrl;
      _identityVerified = p.isIdentityVerified;
    }
  }

  /// 신원 인증 화면으로 이동(저장된 펫만). 완료 시 상태 갱신. 인증 성공 여부 반환.
  Future<bool> _openEnroll(String petId, String petName) async {
    final ok = await Navigator.push<bool>(
      context,
      AppPageRoute(
        builder: (_) => PetIdentityEnrollScreen(petId: petId, petName: petName),
      ),
    );
    if (ok == true && mounted) setState(() => _identityVerified = true);
    return ok == true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _speciesCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      !_uploading &&
      _nameCtrl.text.trim().isNotEmpty &&
      _speciesKind != null &&
      _speciesCtrl.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    final file = await StorageService.instance.pickImage();
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final up = await StorageService.instance.upload(file, category: 'pets');
      if (!mounted) return;
      setState(() {
        _imageUrl = up.url;
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _toast('사진 업로드에 실패했어요');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = PetRepository.instance;
      if (_isEdit) {
        await repo.updatePet(
          widget.pet!.id,
          name: _nameCtrl.text.trim(),
          species: _speciesCtrl.text.trim(),
          speciesKind: _speciesKind,
          gender: _gender,
          birthDate: _birthDate,
          bio: _bioCtrl.text.trim(),
          imageUrl: _imageUrl,
        );
      } else {
        final id = await repo.createPet(
          name: _nameCtrl.text.trim(),
          species: _speciesCtrl.text.trim(),
          speciesKind: _speciesKind,
          gender: _gender,
          birthDate: _birthDate,
          bio: _bioCtrl.text.trim(),
          imageUrl: _imageUrl,
        );
        if (!mounted) return;
        // AI 영상 신원 인증을 통과해야만 등록 완료. 미완료면 방금 만든 펫을 취소(삭제).
        final verified = await _openEnroll(id, _nameCtrl.text.trim());
        if (!mounted) return;
        if (!verified) {
          try {
            await PetRepository.instance.deletePet(id);
          } catch (_) {}
          if (!mounted) return;
          setState(() => _saving = false);
          _toast('AI 신원 인증을 완료해야 등록돼요. 다시 시도해주세요');
          return;
        }
        // 가입 화면에서 받아둔 공동보호자 번호로 자동 초대 — 등록·인증이
        // 확정된 뒤에만 발송한다(가입자는 인앱 알림, 미가입자는 SMS).
        var invited = 0;
        for (final ph in widget.draft?.coGuardianPhones ?? const <String>[]) {
          try {
            await PetRepository.instance.invite(id, ph);
            invited++;
          } catch (_) {
            // 개별 실패(중복/형식 등)는 등록 흐름을 막지 않는다.
          }
        }
        if (!mounted) return;
        Navigator.pop(context, true);
        _toast(invited > 0
            ? '반려동물을 등록하고 공동보호자 초대를 보냈어요'
            : '반려동물을 등록했어요');
        return;
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      _toast('수정했어요');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('저장에 실패했어요');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isEdit ? '반려동물 수정' : '반려동물 등록'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('저장',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _avatar()),
              const SizedBox(height: 24),
              const _Label('이름'),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(hintText: '예) 콩이'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              const _Label('종 (필수)'),
              Row(
                children: [
                  _kindChip('dog', '강아지'),
                  const SizedBox(width: 8),
                  _kindChip('cat', '고양이'),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _speciesCtrl,
                decoration:
                    const InputDecoration(hintText: '품종 입력 (예: 말티즈, 코리안숏헤어)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              const _Label('성별'),
              Row(
                children: [
                  _genderChip('male', '수컷'),
                  const SizedBox(width: 8),
                  _genderChip('female', '암컷'),
                ],
              ),
              const SizedBox(height: 16),
              const _Label('생년월일'),
              InkWell(
                onTap: _pickBirthDate,
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
                      const Icon(Icons.cake_outlined,
                          color: AppColors.primaryDark, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _birthDate == null
                            ? '선택 안 함'
                            : '${_birthDate!.year}년 ${_birthDate!.month}월 ${_birthDate!.day}일',
                        style: TextStyle(
                          fontSize: 14,
                          color: _birthDate == null
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _Label('소개 (선택)'),
              TextField(
                controller: _bioCtrl,
                maxLines: 4,
                decoration:
                    const InputDecoration(hintText: '아이를 소개해주세요'),
              ),
              if (_isEdit && _isOwner) ...[
                const SizedBox(height: 24),
                const _Label('신원 인증'),
                _identityCard(),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    return GestureDetector(
      onTap: _uploading ? null : _pickImage,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(40),
          image: _imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: _uploading
            ? const Center(child: CircularProgressIndicator())
            : (_imageUrl == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined,
                          color: AppColors.primaryDark, size: 28),
                      SizedBox(height: 4),
                      Text('사진',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.primaryDark)),
                    ],
                  )
                : null),
      ),
    );
  }

  Widget _identityCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(_identityVerified ? Icons.verified : Icons.videocam_outlined,
              color: _identityVerified
                  ? AppColors.primary
                  : AppColors.textTertiary,
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _identityVerified
                  ? '신원 인증이 완료됐어요. 게시글 사진이 이 아이와 대조됩니다.'
                  : '산책·돌봄·분양 게시글을 쓰려면 무작위 동작 임무 영상으로 신원 인증을 해야 해요.',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () =>
                _openEnroll(widget.pet!.id, _nameCtrl.text.trim()),
            child: Text(_identityVerified ? '다시 인증' : '인증하기'),
          ),
        ],
      ),
    );
  }

  /// 강아지/고양이 2지선다(필수) — 한 번 고르면 비우지 않고 서로 전환만.
  Widget _kindChip(String value, String label) {
    final selected = _speciesKind == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _speciesKind = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryDark : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppColors.primaryDark : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderChip(String value, String label) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = selected ? null : value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: selected ? AppColors.primaryDark : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      initialDate: _birthDate ?? DateTime(now.year - 1),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
