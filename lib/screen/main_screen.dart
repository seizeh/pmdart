import 'package:flutter/material.dart';
import '../motion/motion.dart';
import 'tabs/community_tab.dart';
import 'tabs/map_tab.dart';
import 'tabs/user_search_tab.dart';
import 'tabs/chat_tab.dart';
import 'tabs/my_info_tab.dart';

/// 메인 화면 — 바텀 네비게이션 5탭.
/// 탭 순서: 지도(개발중) / 사용자검색 / 커뮤니티(중앙=기본) / 채팅 / 내정보
/// 기본 진입 탭은 커뮤니티(인덱스 2).
class MainScreen extends StatefulWidget {
  final bool isGuest;
  const MainScreen({super.key, this.isGuest = false});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _index = 2; // 기본 = 커뮤니티
  int _direction = 0; // 마지막 탭 이동 방향(+1 오른쪽, -1 왼쪽)

  // 탭 전환 시 콘텐츠가 이동 방향에서 흘러 들어오는 짧은 모션.
  late final AnimationController _tab = AnimationController(
    vsync: this,
    duration: MotionDurations.base,
    value: 1,
  );
  late final Animation<double> _tabAnim =
      CurvedAnimation(parent: _tab, curve: SpringCurve.standard);

  late final List<Widget> _tabs = [
    const MapTab(),
    const UserSearchTab(),
    CommunityTab(isGuest: widget.isGuest),
    ChatTab(isGuest: widget.isGuest),
    MyInfoTab(isGuest: widget.isGuest),
  ];

  static const _navItems = [
    SpringyNavItem(
        icon: Icons.map_outlined, activeIcon: Icons.map, label: '지도'),
    SpringyNavItem(
        icon: Icons.person_search_outlined,
        activeIcon: Icons.person_search,
        label: '검색'),
    SpringyNavItem(
        icon: Icons.home_outlined, activeIcon: Icons.home, label: '커뮤니티'),
    SpringyNavItem(
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: '채팅'),
    SpringyNavItem(
        icon: Icons.person_outline, activeIcon: Icons.person, label: '내정보'),
  ];

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _direction = i > _index ? 1 : -1;
      _index = i;
    });
    _tab.forward(from: 0); // 새 탭이 방향에서 흘러 들어옴
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // IndexedStack 으로 각 탭 상태는 보존하고, 전환 순간에만 방향성 있게 흘려 보낸다.
      body: AnimatedBuilder(
        animation: _tabAnim,
        builder: (context, child) {
          final t = _tabAnim.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(_direction * (1 - t) * 28, 0),
              child: child,
            ),
          );
        },
        child: IndexedStack(index: _index, children: _tabs),
      ),
      bottomNavigationBar: SpringyNavBar(
        currentIndex: _index,
        onTap: _select,
        items: _navItems,
      ),
    );
  }
}
