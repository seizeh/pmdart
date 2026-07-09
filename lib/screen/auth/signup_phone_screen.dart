import 'package:flutter/material.dart';
import '../../motion/motion.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../services/phone_auth_service.dart';
import '../../services/auth_service.dart';
import '../main_screen.dart';
import '../terms_screen.dart';
import 'login_screen.dart';

/// 회원가입 — 전화 OTP 기반 다단계 흐름.
/// 1) 약관 동의 (필수 전부 동의해야 다음 진행 가능)
/// 2) 전화번호 입력 → SMS 코드 발송 (phone_verifications.purpose='signup')
/// 3) 6자리 코드 검증
/// 4) 아이디·비밀번호·닉네임
/// 5) 사용자 유형 + 펫 등록 (선택, pet_owner 인 경우)
class SignupPhoneScreen extends StatefulWidget {
  const SignupPhoneScreen({super.key});

  @override
  State<SignupPhoneScreen> createState() => _SignupPhoneScreenState();
}

class _SignupPhoneScreenState extends State<SignupPhoneScreen> {
  int _step = 0; // 0: 동의 → 1: 전화 → 2: 코드 → 3: 정보 → 4: 유형/펫
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  String _userType = 'pet_owner';
  final List<TextEditingController> _coGuardianCtrls = [];

  // 약관 동의 상태 — 필수 4개(연령·이용약관·위치약관·개인정보)가 모두 체크돼야
  // 전화번호 인증 단계로 진행할 수 있다. 마케팅은 선택.
  bool _agreeAge = false;
  bool _agreeTos = false;
  bool _agreeLbs = false;
  bool _agreePrivacy = false;
  bool _agreeMarketing = false;
  // 문서형 약관은 끝까지 읽어야(뷰어에서 "동의합니다") 체크할 수 있다.
  bool _readTos = false;
  bool _readLbs = false;
  bool _readPrivacy = false;

  bool get _allRequiredAgreed =>
      _agreeAge && _agreeTos && _agreeLbs && _agreePrivacy;
  bool get _allAgreed => _allRequiredAgreed && _agreeMarketing;

  bool _loading = false; // 발송/검증 진행 중

  bool _checkingId = false; // 아이디 중복확인 진행 중
  bool _idAvailable = false; // 현재 입력된 아이디가 사용 가능으로 확인됨
  String? _idCheckMsg; // 중복확인 결과 안내 문구
  bool _idCheckOk = false; // 결과 문구 색상용(true=초록/사용가능)

  static final RegExp _phoneRe = RegExp(r'^01\d{8,9}$');
  static final RegExp _usernameRe = RegExp(r'^[A-Za-z0-9]{4,20}$');

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
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
        title: Text('회원가입  ${_step + 1} / 5'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressBar(step: _step, total: 5),
              const SizedBox(height: 32),
              Expanded(child: _stepContent()),
              ElevatedButton(
                onPressed:
                    _loading || (_step == 0 && !_allRequiredAgreed)
                        ? null
                        : _next,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.textOnPrimary,
                        ),
                      )
                    : Text(switch (_step) {
                        0 => '동의하고 계속하기',
                        1 => '인증번호 받기',
                        4 => '가입 완료',
                        _ => '다음',
                      }),
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
        return _consentStep();
      case 1:
        return _phoneStep();
      case 2:
        return _codeStep();
      case 3:
        return _profileStep();
      case 4:
        return _petStep();
    }
    return const SizedBox.shrink();
  }

  // ── 0단계: 약관 동의 — 필수 전부 동의해야 전화번호 인증으로 진행 ──

  Widget _consentStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '서비스 이용을 위해\n동의가 필요해요',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),
          // 전체 동의 — 아직 안 읽은 약관은 순서대로 열어 끝까지 읽게 한다.
          InkWell(
            onTap: _toggleAll,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _allAgreed
                    ? AppColors.primarySoft.withValues(alpha: 0.3)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _allAgreed ? AppColors.primary : AppColors.border,
                  width: _allAgreed ? 1.5 : 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _allAgreed
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: _allAgreed
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '전체 동의',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ConsentRow(
            checked: _agreeAge,
            required_: true,
            label: '만 14세 이상입니다',
            onChanged: (v) => setState(() => _agreeAge = v),
          ),
          _ConsentRow(
            checked: _agreeTos,
            required_: true,
            label: '서비스 이용약관 동의',
            onChanged: (v) => _setDocAgree(_Doc.tos, v),
            onView: () => _readDoc(_Doc.tos),
          ),
          _ConsentRow(
            checked: _agreeLbs,
            required_: true,
            label: '위치기반서비스 이용약관 동의',
            onChanged: (v) => _setDocAgree(_Doc.lbs, v),
            onView: () => _readDoc(_Doc.lbs),
          ),
          _ConsentRow(
            checked: _agreePrivacy,
            required_: true,
            label: '개인정보 수집·이용 동의',
            onChanged: (v) => _setDocAgree(_Doc.privacy, v),
            onView: () => _readDoc(_Doc.privacy),
          ),
          _ConsentRow(
            checked: _agreeMarketing,
            required_: false,
            label: '마케팅 정보 수신 동의',
            onChanged: (v) => setState(() => _agreeMarketing = v),
          ),
          const SizedBox(height: 8),
          const Text(
            '필수 항목에 모두 동의해야 가입을 진행할 수 있어요.\n'
            '약관은 끝까지 읽어야 동의할 수 있습니다.\n'
            '마케팅 수신은 동의하지 않아도 이용에 제한이 없습니다.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary,
                height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 문서형 약관 체크 토글. 해제는 자유, 체크는 끝까지 읽은 뒤에만.
  void _setDocAgree(_Doc doc, bool v) {
    if (!v) {
      setState(() => _docState(doc).agree(false));
      return;
    }
    if (_docState(doc).read) {
      setState(() => _docState(doc).agree(true));
    } else {
      _readDoc(doc); // 아직 안 읽음 → 뷰어를 열어 끝까지 읽고 동의하게 한다
    }
  }

  /// 약관 뷰어(읽기 게이트) 열기. "동의합니다"(끝까지 스크롤 후)로 닫으면
  /// 읽음 + 동의 처리. 뒤로가기로 닫으면 아무 변화 없음.
  Future<bool> _readDoc(_Doc doc) async {
    final agreed = await Navigator.push<bool>(
      context,
      AppPageRoute(
        builder: (_) => switch (doc) {
          _Doc.tos => TermsScreen.service(agree: true),
          _Doc.lbs => TermsScreen.location(agree: true),
          _Doc.privacy => TermsScreen.privacy(agree: true),
        },
      ),
    );
    if (agreed == true && mounted) {
      setState(() {
        _docState(doc)
          ..markRead()
          ..agree(true);
      });
      return true;
    }
    return false;
  }

  ({bool read, void Function() markRead, void Function(bool) agree}) _docState(
      _Doc doc) {
    return switch (doc) {
      _Doc.tos => (
          read: _readTos,
          markRead: () => _readTos = true,
          agree: (v) => _agreeTos = v,
        ),
      _Doc.lbs => (
          read: _readLbs,
          markRead: () => _readLbs = true,
          agree: (v) => _agreeLbs = v,
        ),
      _Doc.privacy => (
          read: _readPrivacy,
          markRead: () => _readPrivacy = true,
          agree: (v) => _agreePrivacy = v,
        ),
    };
  }

  /// 전체 동의: 모두 켜져 있으면 전체 해제. 아니면 안 읽은 약관을 순서대로
  /// 읽게 한 뒤(중간에 닫으면 중단) 나머지 항목까지 일괄 동의.
  Future<void> _toggleAll() async {
    if (_allAgreed) {
      setState(() {
        _agreeAge = false;
        _agreeTos = false;
        _agreeLbs = false;
        _agreePrivacy = false;
        _agreeMarketing = false;
      });
      return;
    }
    for (final doc in _Doc.values) {
      if (_docState(doc).read) continue;
      if (!await _readDoc(doc)) return; // 끝까지 안 읽고 나가면 중단
      if (!mounted) return;
    }
    setState(() {
      _agreeAge = true;
      _agreeTos = true;
      _agreeLbs = true;
      _agreePrivacy = true;
      _agreeMarketing = true;
    });
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _idCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                      labelText: '아이디',
                      hintText: '영문/숫자 4~20자'),
                  // 입력이 바뀌면 직전 중복확인 결과는 무효화
                  onChanged: (_) {
                    if (_idAvailable || _idCheckMsg != null) {
                      setState(() {
                        _idAvailable = false;
                        _idCheckMsg = null;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _checkingId ? null : _checkUsername,
                  child: _checkingId
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('중복확인'),
                ),
              ),
            ],
          ),
          if (_idCheckMsg != null) ...[
            const SizedBox(height: 6),
            Text(
              _idCheckMsg!,
              style: TextStyle(
                fontSize: 12,
                color: _idCheckOk ? AppColors.primaryDark : AppColors.danger,
              ),
            ),
          ],
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
        // 필수 동의 완료 → 전화번호 인증으로 (버튼 자체가 미동의 시 비활성).
        if (!_allRequiredAgreed) return;
        setState(() => _step = 1);
      case 1:
        await _sendCode();
      case 2:
        await _verifyCode();
      case 3:
        if (!_validateProfile()) return;
        setState(() => _step = 4);
      case 4:
        await _completeSignup();
    }
  }

  /// 마지막 단계 → 계정 생성(users INSERT) 후 메인으로.
  Future<void> _completeSignup() async {
    setState(() => _loading = true);
    final result = await PhoneAuthService.instance.signUp(
      username: _idCtrl.text.trim(),
      password: _pwCtrl.text,
      nickname: _nickCtrl.text.trim(),
      userType: _userType,
      phone: _phoneCtrl.text.trim(),
      marketingOptIn: _agreeMarketing,
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
          AppPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } else {
        // 가입은 됐지만 자동 로그인 실패(예: 서버 JWT 설정 누락) → 로그인 화면으로.
        // 세션 없이 메인에 진입하면 데이터가 안 보이므로 진입을 막는다.
        _toast('가입이 완료됐어요. 로그인해주세요.');
        Navigator.pushAndRemoveUntil(
          context,
          AppPageRoute(builder: (_) => const LoginScreen()),
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
        setState(() => _step = 3);
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

  /// 아이디 중복확인. 사용 가능하면 _idAvailable=true 로 표시.
  Future<void> _checkUsername() async {
    final id = _idCtrl.text.trim();
    if (!_usernameRe.hasMatch(id)) {
      setState(() {
        _idAvailable = false;
        _idCheckOk = false;
        _idCheckMsg = '아이디는 영문/숫자 4~20자로 입력해주세요';
      });
      return;
    }
    setState(() => _checkingId = true);
    final result = await PhoneAuthService.instance.checkUsername(id);
    if (!mounted) return;
    setState(() {
      _checkingId = false;
      if (!result.ok) {
        _idAvailable = false;
        _idCheckOk = false;
        _idCheckMsg = '확인에 실패했어요. 잠시 후 다시 시도해주세요';
      } else if (result.available) {
        _idAvailable = true;
        _idCheckOk = true;
        _idCheckMsg = '사용 가능한 아이디예요';
      } else {
        _idAvailable = false;
        _idCheckOk = false;
        _idCheckMsg = '이미 사용 중인 아이디예요';
      }
    });
  }

  bool _validateProfile() {
    if (!_usernameRe.hasMatch(_idCtrl.text.trim())) {
      _toast('아이디는 영문/숫자 4~20자로 입력해주세요');
      return false;
    }
    if (!_idAvailable) {
      _toast('아이디 중복확인을 해주세요');
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

/// 동의 항목 한 줄 — 체크 + [필수/선택] 라벨 + (전문 보기).
/// 읽기 게이트가 걸린 문서형 약관.
enum _Doc { tos, lbs, privacy }

class _ConsentRow extends StatelessWidget {
  final bool checked;
  final bool required_;
  final String label;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onView;

  const _ConsentRow({
    required this.checked,
    required this.required_,
    required this.label,
    required this.onChanged,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.check_circle_outline,
              size: 22,
              color: checked ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(width: 10),
            Text(
              required_ ? '[필수]' : '[선택]',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: required_ ? AppColors.primaryDark : AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (onView != null)
              GestureDetector(
                onTap: onView,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '보기',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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