import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
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

class _MainScreenState extends State<MainScreen> {
  int _index = 2; // 기본 = 커뮤니티

  late final List<Widget> _tabs = [
    const MapTab(),
    const UserSearchTab(),
    CommunityTab(isGuest: widget.isGuest),
    ChatTab(isGuest: widget.isGuest),
    MyInfoTab(isGuest: widget.isGuest),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: '지도',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_search_outlined),
                activeIcon: Icon(Icons.person_search),
                label: '사용자 검색',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: '커뮤니티',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline),
                activeIcon: Icon(Icons.chat_bubble),
                label: '채팅',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: '내정보',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
