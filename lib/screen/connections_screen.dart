import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/social.dart';
import '../services/social_repository.dart';
import '../widgets/user_tile.dart';

/// 내 연결(팔로우) 목록 — Pawing(내가 팔로우) / Pawmate(나를 팔로우) 탭.
/// 각 항목에서 채팅 시작 / 팔로우 토글 가능.
class ConnectionsScreen extends StatelessWidget {
  final int initialIndex; // 0=Pawing, 1=Pawmate
  const ConnectionsScreen({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('내 친구'),
          bottom: const TabBar(
            labelColor: AppColors.primaryDark,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'Pawing (내가 팔로우)'),
              Tab(text: 'Pawmate (나를 팔로우)'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ConnectionList(mode: _Mode.pawing),
            _ConnectionList(mode: _Mode.pawmate),
          ],
        ),
      ),
    );
  }
}

enum _Mode { pawing, pawmate }

class _ConnectionList extends StatefulWidget {
  final _Mode mode;
  const _ConnectionList({required this.mode});

  @override
  State<_ConnectionList> createState() => _ConnectionListState();
}

class _ConnectionListState extends State<_ConnectionList>
    with AutomaticKeepAliveClientMixin {
  final _repo = SocialRepository.instance;
  List<Connection> _items = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = widget.mode == _Mode.pawing
          ? await _repo.fetchPawing()
          : await _repo.fetchPawmate();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '목록을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _empty(_error!, retry: true);
    }
    if (_items.isEmpty) {
      return _empty(widget.mode == _Mode.pawing
          ? '아직 팔로우한 사람이 없어요'
          : '아직 나를 팔로우한 사람이 없어요');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) => UserTile(connection: _items[i]),
      ),
    );
  }

  Widget _empty(String msg, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.group_outlined,
              size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(msg,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}
