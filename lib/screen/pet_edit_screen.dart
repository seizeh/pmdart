import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show MockPet;
import '../services/pet_repository.dart';
import '../services/storage_service.dart';

/// 반려동물 등록/수정 화면. [pet] 가 있으면 수정, 없으면 신규 등록.
class PetEditScreen extends StatefulWidget {
  final MockPet? pet;
  const PetEditScreen({super.key, this.pet});

  @override
  State<PetEditScreen> createState() => _PetEditScreenState();
}

class _PetEditScreenState extends State<PetEditScreen> {
  final _nameCtrl = TextEditingController();
  final _speciesCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _gender;
  DateTime? _birthDate;
  bool _neutered = false;
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  bool get _isEdit => widget.pet != null;

  @override
  void initState() {
    super.initState();
    final p = widget.pet;
    if (p != null) {
      _nameCtrl.text = p.name;
      _speciesCtrl.text = p.species;
      _bioCtrl.text = p.bio ?? '';
      _gender = p.gender;
      _birthDate = p.birthDate;
      _neutered = p.isNeutered;
      _imageUrl = p.imageUrl;
    }
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
          gender: _gender,
          birthDate: _birthDate,
          bio: _bioCtrl.text.trim(),
          isNeutered: _neutered,
          imageUrl: _imageUrl,
        );
      } else {
        await repo.createPet(
          name: _nameCtrl.text.trim(),
          species: _speciesCtrl.text.trim(),
          gender: _gender,
          birthDate: _birthDate,
          bio: _bioCtrl.text.trim(),
          isNeutered: _neutered,
          imageUrl: _imageUrl,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      _toast(_isEdit ? '수정했어요' : '반려동물을 등록했어요');
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
      backgroundColor: AppColors.background,
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
              const _Label('종'),
              TextField(
                controller: _speciesCtrl,
                decoration: const InputDecoration(hintText: '예) 말티즈'),
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
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('중성화 완료',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                value: _neutered,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _neutered = v),
              ),
              const SizedBox(height: 8),
              const _Label('소개 (선택)'),
              TextField(
                controller: _bioCtrl,
                maxLines: 4,
                decoration:
                    const InputDecoration(hintText: '아이를 소개해주세요'),
              ),
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
