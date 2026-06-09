import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/social.dart';
import '../../services/social_repository.dart';
import '../../widgets/user_tile.dart';

/// 사용자 검색 탭 — 닉네임/아이디로 검색(입력 즉시) 후 팔로우/채팅.
class UserSearchTab extends StatefulWidget {
  const UserSearchTab({super.key});

  @override
  State<UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends State<UserSearchTab> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _reqId = 0; // 응답 순서 꼬임 방지

  List<Connection> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final myReq = ++_reqId;
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final res = await SocialRepository.instance.searchUsers(q);
      if (!mounted || myReq != _reqId) return; // 더 최신 검색이 있으면 무시
      setState(() {
        _results = res;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || myReq != _reqId) return;
      setState(() {
        _results = [];
        _loading = false;
      });
    }
  }

  void _clear() {
    _ctrl.clear();
    _debounce?.cancel();
    setState(() {
      _results = [];
      _searched = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (v) {
                  final q = v.trim();
                  if (q.isNotEmpty) _runSearch(q);
                },
                decoration: InputDecoration(
                  hintText: '닉네임 또는 아이디로 검색',
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.textSecondary),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.textTertiary),
                          onPressed: _clear,
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_searched) {
      return _hint('닉네임이나 아이디를 입력해\n보호자를 찾아보세요');
    }
    if (_results.isEmpty) {
      return _hint('검색 결과가 없어요');
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => UserTile(connection: _results[i]),
    );
  }

  Widget _hint(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_search_outlined,
              size: 56, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
