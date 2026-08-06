import 'package:flutter/material.dart';

import '../models/social.dart';
import '../motion/motion.dart';
import '../services/social_repository.dart';
import '../theme/app_palette.dart';
import '../widgets/profile_square_card.dart';
import 'user_profile_screen.dart';

/// 내 연결(팔로우) 목록 — Pawing(내가 팔로우) / Pawmate(나를 팔로우).
///
/// 종전에는 탭 2개짜리 한 화면이었다. 내정보의 Pawing·Pawmate 버튼이 **서로 다른
/// 버튼인데 같은 화면**을 열어(선택 탭만 달랐다) 왜 둘로 나뉘어 있는지 알 수
/// 없었다. 이제 버튼마다 자기 목록만 연다.
class ConnectionsScreen extends StatelessWidget {
  /// 0=Pawing, 1=Pawmate. 호출부가 이미 이 값을 넘기고 있어 시그니처를 유지한다.
  final int initialIndex;
  const ConnectionsScreen({super.key, this.initialIndex = 0});

  bool get _isPawing => initialIndex == 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text(_isPawing ? 'Pawing' : 'Pawmate')),
      body: _ConnectionList(mode: _isPawing ? _Mode.pawing : _Mode.pawmate),
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

class _ConnectionListState extends State<_ConnectionList> {
  final _repo = SocialRepository.instance;
  List<Connection> _items = [];
  bool _loading = true;
  String? _error;

  // 타일 자리에서 프로필이 펼쳐지고/그 자리로 축소되는 전환(사용자 검색과 동일).
  final _tileKeys = <String, GlobalKey>{};
  String? _openedTileId;

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
    cardRadius: ProfileSquareCard.radius,
    cardBuilder: rect == null ? null : (_) => ProfileSquareCard(connection: c),
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _empty(_error!, retry: true);
    }
    if (_items.isEmpty) {
      return _empty(
        widget.mode == _Mode.pawing ? '아직 팔로우한 사람이 없어요' : '아직 나를 팔로우한 사람이 없어요',
      );
    }
    // 둥근 정사각형 2열 — 사용자 검색과 같은 문법(간격 10, 정사각 비율).
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final c = _items[i];
          final tileId = _tileId(c);
          // 프로필이 열린 카드는 빈자리로 — 축소가 겹침 없이 안착(검색과 동일).
          return Opacity(
            key: _tileKeys.putIfAbsent(tileId, GlobalKey.new),
            opacity: _openedTileId == tileId ? 0 : 1,
            child: ProfileSquareCard(connection: c, onTap: () => _openUser(c)),
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
