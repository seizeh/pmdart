import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 사용자 검색 탭 — 닉네임/아이디로 다른 보호자를 찾는다.
class UserSearchTab extends StatefulWidget {
  const UserSearchTab({super.key});

  @override
  State<UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends State<UserSearchTab> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '사용자 검색',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '닉네임 또는 아이디로 검색',
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_search_outlined,
                          size: 56, color: AppColors.textTertiary),
                      SizedBox(height: 12),
                      Text(
                        '닉네임이나 아이디를 입력해\n보호자를 찾아보세요',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
