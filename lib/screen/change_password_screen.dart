import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../services/auth_service.dart';

/// 비밀번호 변경 — 현재 비밀번호 확인 후 새 비밀번호로 변경.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _loading = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;
    if (current.isEmpty || next.isEmpty) {
      _toast('현재 비밀번호와 새 비밀번호를 입력해주세요');
      return;
    }
    if (next.length < 6) {
      _toast('새 비밀번호는 6자 이상이어야 해요');
      return;
    }
    if (next != confirm) {
      _toast('새 비밀번호가 서로 달라요');
      return;
    }
    if (next == current) {
      _toast('현재 비밀번호와 다른 비밀번호로 설정해주세요');
      return;
    }
    setState(() => _loading = true);
    final result = await AuthService.instance.changePassword(current, next);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.ok) {
      _toast('비밀번호를 변경했어요');
      Navigator.pop(context);
    } else {
      _toast(result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('비밀번호 변경')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _field(
              label: '현재 비밀번호',
              controller: _currentCtrl,
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 16),
            _field(
              label: '새 비밀번호 (6자 이상)',
              controller: _newCtrl,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 16),
            _field(
              label: '새 비밀번호 확인',
              controller: _confirmCtrl,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('변경하기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: context.colors.textTertiary,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}
