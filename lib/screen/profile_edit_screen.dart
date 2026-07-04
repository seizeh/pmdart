import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../models/profile.dart';
import '../services/profile_repository.dart';
import '../services/storage_service.dart';
import '../services/session.dart';
import 'location_verify_screen.dart';

/// 프로필 편집 — 닉네임 + 프로필 사진 + 활동 지역(GPS 인증).
class ProfileEditScreen extends StatefulWidget {
  final String initialNickname;

  /// 활동 지역(동네 인증) 초기 상태. address 는 GPS 인증으로만 바뀐다.
  final String? initialAddress;
  final bool initialVerified;
  const ProfileEditScreen({
    super.key,
    required this.initialNickname,
    this.initialAddress,
    this.initialVerified = false,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nickCtrl =
      TextEditingController(text: widget.initialNickname);
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  // 활동 지역(동네 인증) — GPS 인증 결과를 화면에 즉시 반영하기 위한 로컬 상태.
  late String? _address = widget.initialAddress;
  late bool _verified = widget.initialVerified;
  String? get _regionName =>
      ProfileData.regionNameFromAddress(_address, verified: _verified);

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

  /// 활동 지역은 자유 입력이 아니라 GPS 인증으로만 바뀐다(보안: 게시글 지역 게이팅).
  /// 인증 화면에서 성공(pop true)하면 서버 값이 갱신되므로 다시 조회해 표시한다.
  Future<void> _verifyRegion() async {
    final changed = await Navigator.push<bool>(
      context,
      AppPageRoute(
        builder: (_) => LocationVerifyScreen(currentRegion: _regionName),
      ),
    );
    if (changed != true || !mounted) return;
    try {
      final r = await ProfileRepository.instance.fetchRegion();
      if (!mounted) return;
      setState(() {
        _address = r.address;
        _verified = r.verified;
      });
    } catch (_) {
      // 조회 실패해도 인증 자체는 반영됨(내정보 탭이 새로고침으로 따라잡음).
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
      backgroundColor: Colors.white,
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
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('활동 지역',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _verifyRegion,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 20, color: AppColors.primaryDark),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _verified && _regionName != null
                              ? _regionName!
                              : '지역 미인증',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _verified
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      Text(
                        _verified ? '재인증' : 'GPS로 인증',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '활동 지역은 현재 위치(GPS)로만 인증돼요.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
