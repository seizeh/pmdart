import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/profile_repository.dart';
import '../services/storage_service.dart';
import '../services/session.dart';

/// 프로필 편집 — 닉네임 + 프로필 사진.
class ProfileEditScreen extends StatefulWidget {
  final String initialNickname;
  const ProfileEditScreen({super.key, required this.initialNickname});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nickCtrl =
      TextEditingController(text: widget.initialNickname);
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  @override
  void dispose() {
    _nickCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving && !_uploading && _nickCtrl.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    final file = await StorageService.instance.pickImage();
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final up = await StorageService.instance.upload(file, category: 'profile');
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
      await ProfileRepository.instance.updateProfile(
        nickname: _nickCtrl.text.trim(),
        profileImageUrl: _imageUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      _toast('프로필을 수정했어요');
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
    final initial = _nickCtrl.text.isEmpty
        ? (SessionManager.instance.user?.nickname ?? '?')
        : _nickCtrl.text;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('프로필 편집'),
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
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              GestureDetector(
                onTap: _uploading ? null : _pickImage,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                    image: _imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _uploading
                      ? const Center(child: CircularProgressIndicator())
                      : (_imageUrl == null
                          ? Center(
                              child: Text(
                                initial.characters.first,
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            )
                          : null),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _uploading ? null : _pickImage,
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('사진 변경'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: const Text('닉네임',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nickCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: '닉네임'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
