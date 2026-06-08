import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../services/phone_auth_service.dart';
import '../../services/auth_service.dart';
import '../main_screen.dart';
import 'login_screen.dart';

/// 회원가입 — 전화 OTP 기반 다단계 흐름.
/// 1) 전화번호 입력 → SMS 코드 발송 (phone_verifications.purpose='signup')
/// 2) 6자리 코드 검증
/// 3) 아이디·비밀번호·닉네임
/// 4) 사용자 유형 + 펫 등록 (선택, pet_owner 인 경우)
class SignupPhoneScreen extends StatefulWidget {
  const SignupPhoneScreen({super.key});

  @override
  State<SignupPhoneScreen> createState() => _SignupPhoneScreenState();
}

class _SignupPhoneScreenState extends State<SignupPhoneScreen> {
  int _step = 0; // 0: 전화 → 1: 코드 → 2: 정보 → 3: 유형/펫
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  String _userType = 'pet_owner';
  final List<TextEditingController> _coGuardianCtrls = [];

  bool _loading = false; // 발송/검증 진행 중

  static final RegExp _phoneRe = RegExp(r'^01\d{8,9}$');

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _nickCtrl.dispose();
    for (final c in _coGuardianCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == 0) {
              Navigator.pop(context);
            } else {
              setState(() => _step--);
            }
          },
        ),
        title: Text('회원가입  ${_step + 1} / 4'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressBar(step: _step, total: 4),
              const SizedBox(height: 32),
              Expanded(child: _stepContent()),
              ElevatedButton(
                onPressed: _loading ? null : _next,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.textOnPrimary,
                        ),
                      )
                    : Text(_step == 3
                        ? '가입 완료'
                        : (_step == 0 ? '인증번호 받기' : '다음')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case 0:
        return _phoneStep();
      case 1:
        return _codeStep();
      case 2:
        return _profileStep();
      case 3:
        return _petStep();
    }
    return const SizedBox.shrink();
  }

  Widget _phoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '전화번호를\n입력해주세요',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'SMS로 6자리 인증코드를 보내드려요',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: const InputDecoration(
            hintText: '01012345678',
            prefixIcon: Icon(Icons.phone_outlined,
                color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '인증코드를\n입력해주세요',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${_formatPhone(_phoneCtrl.text)}로 보낸 6자리 코드',
          style: const TextStyle(
              fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '------',
            counterText: '',
          ),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 12,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: _loading ? null : _resend,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('다시 보내기'),
          ),
        ),
      ],
    );
  }

  Widget _profileStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '프로필 정보를\n설정해주세요',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
                labelText: '아이디',
                hintText: '영문/숫자 4자 이상'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwCtrl,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: '비밀번호',
                hintText: '대/소문자 + 특수문자 포함 8자 이상'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nickCtrl,
            decoration: const InputDecoration(labelText: '닉네임'),
          ),
        ],
      ),
    );
  }

  Widget _petStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사용자 유형을\n선택해주세요',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),
          _UserTypeOption(
            value: 'pet_owner',
            group: _userType,
            title: '반려동물 보호자',
            subtitle: '동반산책·돌봄·분양까지 모든 카테고리 작성 가능',
            onChanged: (v) => setState(() => _userType = v),
          ),
          const SizedBox(height: 10),
          _UserTypeOption(
            value: 'no_pet',
            group: _userType,
            title: '반려동물 미보유',
            subtitle: '자유·입양 글 작성 가능, 다른 활동은 지원/관전 위주',
            onChanged: (v) => setState(() => _userType = v),
          ),
          const SizedBox(height: 10),
          _UserTypeOption(
            value: 'business',
            group: _userType,
            title: '업체 / 사업자',
            subtitle: '미용실·병원·카페 등 운영자',
            onChanged: (v) => setState(() => _userType = v),
          ),
          if (_userType == 'pet_owner') ...[
            const SizedBox(height: 28),
            const Text(
              '공동보호자가 있다면 전화번호를 입력해주세요',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '입력한 번호로 자동 초대장이 발송됩니다 (선택)',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ..._coGuardianCtrls.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: e.value,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        hintText: '01012345678',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _coGuardianCtrls.removeAt(e.key);
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            )),
            OutlinedButton.icon(
              onPressed: () => setState(() =>
                  _coGuardianCtrls.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('공동보호자 추가'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _next() async {
    switch (_step) {
      case 0:
        await _sendCode();
      case 1:
        await _verifyCode();
      case 2:
        if (!_validateProfile()) return;
        setState(() => _step = 3);
      case 3:
        await _completeSignup();
    }
  }

  /// 3단계 → 계정 생성(users INSERT) 후 메인으로.
  Future<void> _completeSignup() async {
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.signUp(
      username: _idCtrl.text.trim(),
      password: _pwCtrl.text,
      nickname: _nickCtrl.text.trim(),
      userType: _userType,
      phone: _phoneCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.ok) {
      // TODO: 공동보호자 초대(_coGuardianCtrls) 발송은 후속 연동 지점.
      // 가입 직후 자동 로그인하여 세션(JWT) 발급.
      final loginResult =
          await AuthService.instance.login(_idCtrl.text.trim(), _pwCtrl.text);
      if (!mounted) return;
      if (loginResult.ok) {
        // 세션 발급 성공 → 메인으로.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } else {
        // 가입은 됐지만 자동 로그인 실패(예: 서버 JWT 설정 누락) → 로그인 화면으로.
        // 세션 없이 메인에 진입하면 데이터가 안 보이므로 진입을 막는다.
        _toast('가입이 완료됐어요. 로그인해주세요.');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } else {
      _toast(result.message);
      // 중복/유형 오류는 정보 입력 단계로 되돌려 수정 유도
      if (result.errorCode == 'username_taken' ||
          result.errorCode == 'nickname_taken' ||
          result.errorCode == 'invalid_username' ||
          result.errorCode == 'invalid_password' ||
          result.errorCode == 'invalid_nickname') {
        setState(() => _step = 2);
      }
    }
  }

  /// 0단계 → 인증코드 발송 후 1단계로.
  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (!_phoneRe.hasMatch(phone)) {
      _toast('올바른 전화번호를 입력해주세요 (예: 01012345678)');
      return;
    }
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.sendCode(phone);
    if (!mounted) return;
    setState(() => _loading = false);
    _toast(result.message);
    if (result.ok) {
      _codeCtrl.clear();
      setState(() => _step = 1);
    }
  }

  /// 1단계 → 인증코드 검증 후 2단계로.
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _toast('6자리 인증번호를 입력해주세요');
      return;
    }
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance
        .verifyCode(_phoneCtrl.text.trim(), code);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.verified) {
      setState(() => _step = 2);
    } else {
      _toast(result.message);
    }
  }

  /// 인증코드 재발송.
  Future<void> _resend() async {
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.sendCode(_phoneCtrl.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    _toast(result.message);
  }

  bool _validateProfile() {
    if (_idCtrl.text.trim().length < 4) {
      _toast('아이디를 4자 이상 입력해주세요');
      return false;
    }
    if (_pwCtrl.text.length < 8) {
      _toast('비밀번호를 8자 이상 입력해주세요');
      return false;
    }
    if (_nickCtrl.text.trim().isEmpty) {
      _toast('닉네임을 입력해주세요');
      return false;
    }
    return true;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatPhone(String raw) {
    if (raw.length < 7) return raw;
    if (raw.length == 11) {
      return '${raw.substring(0, 3)}-${raw.substring(3, 7)}-${raw.substring(7)}';
    }
    return raw;
  }
}

class _ProgressBar extends StatelessWidget {
  final int step;
  final int total;
  const _ProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        );
      }),
    );
  }
}

class _UserTypeOption extends StatelessWidget {
  final String value;
  final String group;
  final String title;
  final String subtitle;
  final ValueChanged<String> onChanged;

  const _UserTypeOption({
    required this.value,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == group;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft.withValues(alpha: 0.3) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}