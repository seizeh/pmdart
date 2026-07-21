import 'package:flutter/material.dart';

import '../models/social.dart';
import '../motion/motion.dart';
import '../services/social_repository.dart';
import '../theme/app_palette.dart';
import '../widgets/user_tile.dart';
import 'user_profile_screen.dart';

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
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: const Text('내 친구'),
          bottom: TabBar(
            labelColor: context.colors.primaryDark,
            unselectedLabelColor: context.colors.textTertiary,
            indicatorColor: context.colors.primary,
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

  // 타일 자리에서 프로필이 펼쳐지고/그 자리로 축소되는 전환(사용자 검색과 동일).
  final _tileKeys = <String, GlobalKey>{};
  String? _openedTileId;

  @override
  bool get wantKeepAlive => true;

  Rect? _tileRect(String id) {
    final ctx = _tileKeys[id]?.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // 같은 사용자의 개인/업체 팔로우 행이 공존한다 — 타일 id 에 얼굴을 포함해야
  // GlobalKey 가 충돌하지 않는다(충돌하면 한 행이 렌더링에서 사라짐).
  String _tileId(Connection c) =>
      'user:${c.userId}:${c.isBusiness ? 'biz' : 'personal'}';

  Future<void> _openUser(Connection c) async {
    final tileId = _tileId(c);
    final rect = _tileRect(tileId);
    if (rect != null) setState(() => _openedTileId = tileId);
    await Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => _profilePage(c, null))
          : CollapseRoute<void>(builder: (_) => _profilePage(c, rect)),
    );
    if (mounted) setState(() => _openedTileId = null);
  }

  Widget _profilePage(Connection c, Rect? rect) => UserProfileScreen(
    userId: c.userId,
    // 업체 팔로우 행은 미리보기부터 상호로 — 닉네임 비노출.
    previewNickname: c.businessName ?? c.nickname,
    // 업체 행만 업체 얼굴 — 개인 행은 개인 얼굴 고정(연결 차단).
    forcePersonalFace: c.businessName == null,
    originRect: rect,
    cardBuilder: rect == null ? null : (_) => UserTile(connection: c),
  );

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
      return _empty(
        widget.mode == _Mode.pawing ? '아직 팔로우한 사람이 없어요' : '아직 나를 팔로우한 사람이 없어요',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      // 타일 간격은 사용자 검색과 동일하게 10 — 구분선 대신 여백으로 분리.
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final c = _items[i];
          final tileId = _tileId(c);
          // 프로필이 열린 타일은 빈자리로 — 축소가 겹침 없이 안착(검색과 동일).
          return Opacity(
            key: _tileKeys.putIfAbsent(tileId, GlobalKey.new),
            opacity: _openedTileId == tileId ? 0 : 1,
            child: UserTile(connection: c, onTap: () => _openUser(c)),
          );
        },
      ),
    );
  }

  Widget _empty(String msg, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_outlined,
            size: 48,
            color: context.colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
          ),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}
