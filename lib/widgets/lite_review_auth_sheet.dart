import 'dart:async';

import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../screen/terms_screen.dart';
import '../services/phone_auth_service.dart';
import '../theme/app_palette.dart';

/// 간이 회원 인증 시트 (0029) — 비로그인 손님이 후기를 **게시할 때만** 뜬다.
///
/// 설계 의도: 진입 마찰을 최소로. 아이디·비밀번호·닉네임·프로필 없이 전화번호
/// 인증 하나로 끝난다. 대신 이렇게 만든 계정은 비회원 취급이라(users.status='lite')
/// 후기 작성 외에는 아무것도 못 하고, 다음 후기를 쓸 때 인증을 다시 받는다.
///
/// 동의는 체크박스로 **명시적으로** 받는다. 전화번호는 개인정보고, 나중에 정식
/// 회원으로 전환할 때 같은 번호로 이 후기들을 이어붙이는 것까지가 수집 목적이라
/// 그 목적이 동의 항목에 적혀 있어야 한다(서버도 동의 없으면 거부한다).
///
/// 성공 시 [LiteSignupResult] 를 pop — 호출부는 그 토큰으로 게시를 진행한다.
Future<LiteSignupResult?> showLiteReviewAuthSheet(BuildContext context) {
  return showModalBottomSheet<LiteSignupResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _LiteReviewAuthSheet(),
  );
}

class _LiteReviewAuthSheet extends StatefulWidget {
  const _LiteReviewAuthSheet();

  @override
  State<_LiteReviewAuthSheet> createState() => _LiteReviewAuthSheetState();
}

class _LiteReviewAuthSheetState extends State<_LiteReviewAuthSheet> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _sent = false; // 코드 발송 완료 → 코드 입력 단계
  bool _busy = false;
  bool _consent = false;
  int _cooldown = 0; // 재발송까지 남은 초(서버 rate limit 60초와 맞춤)
  Timer? _timer;

  // 동의문 안의 링크 — 인식기는 위젯 수명과 함께 정리해야 샌다.
  // 전문은 번들 에셋을 그대로 띄운다(앱의 다른 약관 링크와 같은 방식).
  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => _openTerms(TermsScreen.liteReview());
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => _openTerms(TermsScreen.privacy());

  @override
  void dispose() {
    _timer?.cancel();
    _termsTap.dispose();
    _privacyTap.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _phone => _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
  bool get _phoneValid => RegExp(r'^01\d{8,9}$').hasMatch(_phone);
  bool get _codeValid => RegExp(r'^\d{6}$').hasMatch(_codeCtrl.text.trim());

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (!_phoneValid || _busy || _cooldown > 0) return;
    setState(() => _busy = true);
    final res = await PhoneAuthService.instance.sendCode(
      _phone,
      purpose: 'review',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.message);
      return;
    }
    setState(() => _sent = true);
    _startCooldown();
    _toast('인증번호를 보냈어요');
  }

  Future<void> _confirm() async {
    if (!_codeValid || !_consent || _busy) return;
    setState(() => _busy = true);
    final res = await PhoneAuthService.instance.signUpLite(
      phone: _phone,
      code: _codeCtrl.text.trim(),
      privacyConsent: _consent,
    );
    if (!mounted) return;
    if (!res.ok || res.token == null) {
      setState(() => _busy = false);
      _toast(res.message);
      return;
    }
    Navigator.pop(context, res);
  }

  void _openTerms(TermsScreen screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      // 키보드가 올라와도 입력칸이 가리지 않게.
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '전화번호만 인증하면 바로 남길 수 있어요',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '가입 절차 없이 후기를 남길 수 있어요. 작성자는 '
            '${_maskPreview()} 처럼 일부만 표시돼요.',
            style: TextStyle(fontSize: 13, height: 1.5, color: c.textSecondary),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _phoneCtrl,
            enabled: !_sent,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '휴대폰 번호',
              hintText: '01012345678',
              suffixIcon: TextButton(
                onPressed: (_phoneValid && !_busy && _cooldown == 0)
                    ? _send
                    : null,
                child: Text(
                  _cooldown > 0 ? '$_cooldown초' : (_sent ? '재발송' : '인증번호 받기'),
                ),
              ),
            ),
          ),
          if (_sent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '인증번호 6자리',
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 12),
          _consentRow(c),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: (_sent && _codeValid && _consent && !_busy)
                ? _confirm
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primaryDark,
              foregroundColor: c.textOnPrimary,
              minimumSize: const Size.fromHeight(50),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '인증하고 후기 남기기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }

  /// 입력한 번호로 표시명 미리보기 — 무엇이 공개되는지 먼저 보여준다.
  /// 서버 app.mask_phone / signup-lite 의 maskPhone 과 같은 규칙이어야 한다.
  String _maskPreview() {
    final d = _phone;
    if (d.length >= 11) {
      return '***-${d[3]}***-**${d.substring(d.length - 2)}';
    }
    if (d.length >= 4) return '***-****-**${d.substring(d.length - 2)}';
    return '***-1***-**78';
  }

  Widget _consentRow(AppPalette c) => InkWell(
    onTap: () => setState(() => _consent = !_consent),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: c.textSecondary,
                  ),
                  children: [
                    const TextSpan(text: '(필수) '),
                    _link('간이 후기 이용조건', _termsTap, c),
                    const TextSpan(text: ' 및 '),
                    _link('전화번호 수집·이용', _privacyTap, c),
                    const TextSpan(
                      text:
                          ' 에 동의합니다. 수집한 번호는 후기 작성자 식별과 '
                          '정식 회원 가입 시 계정 연결에 쓰여요.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  TextSpan _link(String label, TapGestureRecognizer tap, AppPalette c) =>
      TextSpan(
        text: label,
        style: TextStyle(
          color: c.primaryDark,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        ),
        recognizer: tap,
      );
}
