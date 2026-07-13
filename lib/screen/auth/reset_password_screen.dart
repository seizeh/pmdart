import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_palette.dart';
import '../../services/phone_auth_service.dart';

/// 비밀번호 재설정 — 전화 OTP 기반.
/// 1) 전화번호 입력 → SMS 코드 발송 (phone_verifications.purpose='password_reset')
/// 2) 6자리 코드 검증
/// 3) 새 비밀번호 설정 → reset-password (번호로 계정 찾아 갱신 + 전 세션 무효화)
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  int _step = 0; // 0: 전화 → 1: 코드 → 2: 새 비번
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  static const _purpose = 'password_reset';
  static final RegExp _phoneRe = RegExp(r'^01\d{8,9}$');

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.cream,
      appBar: AppBar(
        backgroundColor: context.colors.cream,
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
        title: Text('비밀번호 재설정  ${_step + 1} / 3'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressBar(step: _step, total: 3),
              const SizedBox(height: 32),
              Expanded(child: _stepContent()),
              ElevatedButton(
                onPressed: _loading ? null : _next,
                child: _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: context.colors.textOnPrimary,
                        ),
                      )
                    : Text(
                        _step == 0
                            ? '인증번호 받기'
                            : (_step == 2 ? '비밀번호 변경' : '다음'),
                      ),
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
        return _passwordStep();
    }
    return const SizedBox.shrink();
  }

  Widget _phoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '가입한 전화번호를\n입력해주세요',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'SMS로 6자리 인증코드를 보내드려요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: InputDecoration(
            hintText: '01012345678',
            prefixIcon: Icon(
              Icons.phone_outlined,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '인증코드를\n입력해주세요',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${_formatPhone(_phoneCtrl.text)}로 보낸 6자리 코드',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
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
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 12,
            color: context.colors.primaryDark,
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

  Widget _passwordStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '새 비밀번호를\n설정해주세요',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _pwCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '새 비밀번호',
              hintText: '영문 + 숫자 포함 8자 이상',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: context.colors.textSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwConfirmCtrl,
            obscureText: _obscure,
            onSubmitted: (_) => _loading ? null : _next(),
            decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
          ),
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
        await _submitReset();
    }
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (!_phoneRe.hasMatch(phone)) {
      _toast('올바른 전화번호를 입력해주세요 (예: 01012345678)');
      return;
    }
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.sendCode(
      phone,
      purpose: _purpose,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    _toast(result.message);
    if (result.ok) {
      _codeCtrl.clear();
      setState(() => _step = 1);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _toast('6자리 인증번호를 입력해주세요');
      return;
    }
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.verifyCode(
      _phoneCtrl.text.trim(),
      code,
      purpose: _purpose,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.verified) {
      setState(() => _step = 2);
    } else {
      _toast(result.message);
    }
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.sendCode(
      _phoneCtrl.text.trim(),
      purpose: _purpose,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    _toast(result.message);
  }

  Future<void> _submitReset() async {
    final pw = _pwCtrl.text;
    if (pw.length < 8 ||
        !RegExp(r'[A-Za-z]').hasMatch(pw) ||
        !RegExp(r'\d').hasMatch(pw)) {
      _toast('비밀번호는 영문과 숫자를 포함해 8자 이상이어야 해요');
      return;
    }
    if (pw != _pwConfirmCtrl.text) {
      _toast('새 비밀번호가 서로 달라요');
      return;
    }
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.resetPassword(
      phone: _phoneCtrl.text.trim(),
      newPassword: pw,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.ok) {
      _toast('비밀번호가 변경됐어요. 새 비밀번호로 로그인해주세요.');
      Navigator.pop(context); // 로그인 화면으로 복귀
    } else {
      _toast(result.message);
      // 인증 만료 등은 처음 단계로 되돌려 재인증 유도
      if (result.errorCode == 'phone_not_verified') {
        setState(() => _step = 0);
      }
    }
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
              color: active ? context.colors.primary : context.colors.border,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        );
      }),
    );
  }
}
