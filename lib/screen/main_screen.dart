import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../services/keyboard_barrier.dart';
import '../theme/app_palette.dart';
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

  /// 외부(푸시 딥링크 등)에서의 탭 전환 요청 — 인덱스를 넣으면 화면이 전환 후
  /// null 로 리셋한다. 딥링크가 상세를 얹기 전에 "뒤로 갔을 때 보일 탭"을 맞출 때 사용.
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  static const tabMap = 0, tabSearch = 1, tabCommunity = 2, tabChat = 3, tabMyInfo = 4;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _index = 2; // 기본 = 커뮤니티
  int _direction = 0; // 마지막 탭 이동 방향(+1 오른쪽, -1 왼쪽)

  // 하단 네비게이션 바 표시 여부. 커뮤니티에서 아래로 스크롤 시 숨고 위로 올리면 복귀.
  final _navVisible = ValueNotifier<bool>(true);

  // 탭 전환 시 콘텐츠가 이동 방향에서 흘러 들어오는 짧은 모션.
  late final AnimationController _tab = AnimationController(
    vsync: this,
    duration: MotionDurations.base,
    value: 1,
  );
  late final Animation<double> _tabAnim = CurvedAnimation(
    parent: _tab,
    curve: SpringCurve.standard,
  );

  late final List<Widget> _tabs = [
    const MapTab(),
    const UserSearchTab(),
    CommunityTab(isGuest: widget.isGuest, chromeVisible: _navVisible),
    ChatTab(isGuest: widget.isGuest),
    MyInfoTab(isGuest: widget.isGuest, chromeVisible: _navVisible),
  ];

  // 라벨 없는 아이콘 단독 내비 — 앱의 둥근 무드에 맞춘 rounded 계열로 통일
  // (외곽선 아이콘은 각져 보여 제외). 활성/비활성 구분은 색·확대·알약이 담당.
  static const _navItems = [
    SpringyNavItem(icon: Icons.location_on_rounded), // 지도 — 둥근 핀
    SpringyNavItem(icon: Icons.person_search_rounded), // 검색
    SpringyNavItem(icon: Icons.groups_rounded), // 커뮤니티 — 지붕 없는 둥근 형태
    SpringyNavItem(icon: Icons.chat_bubble_rounded), // 채팅
    SpringyNavItem(icon: Icons.person_rounded), // 내정보
  ];

  @override
  void initState() {
    super.initState();
    _syncKeyboardBarrier();
    MainScreen.tabRequest.addListener(_onTabRequest);
    // 화면 생성 전에 들어온 요청(콜드 스타트 딥링크)은 첫 프레임 뒤에 소비.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTabRequest());
  }

  void _onTabRequest() {
    final i = MainScreen.tabRequest.value;
    if (i == null) return;
    MainScreen.tabRequest.value = null;
    if (mounted && i >= 0 && i < _tabs.length) _select(i);
  }

  // 지도 탭(index 0)은 자동완성 제안 탭을 위해 전역 키보드 배리어를 끈다.
  void _syncKeyboardBarrier() => keyboardBarrierEnabled.value = _index != 0;

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _direction = i > _index ? 1 : -1;
      _index = i;
    });
    _navVisible.value = true; // 탭 전환 시 바는 항상 보이게 복귀
    _syncKeyboardBarrier();
    _tab.forward(from: 0); // 새 탭이 방향에서 흘러 들어옴
  }

  @override
  void dispose() {
    MainScreen.tabRequest.removeListener(_onTabRequest);
    _tab.dispose();
    _navVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      // body 를 하단 바 뒤까지 확장 → 바가 숨을 때 콘텐츠가 화면 끝까지 차서
      // 흰 여백이 생기지 않는다(각 탭은 바 높이만큼 하단 패딩으로 가림 방지).
      extendBody: true,
      // 키보드 리사이즈 금지 — 켜두면 키보드가 오르내리는 매 프레임 IndexedStack 의
      // 5개 탭 전부(지도 플랫폼뷰 포함)가 재레이아웃돼 검색 중 스크롤이 심하게 끊긴다.
      // 탭 내 입력 필드(커뮤니티·사용자 검색)는 모두 상단이라 가려질 것이 없다.
      resizeToAvoidBottomInset: false,
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
      // 아래로 스크롤 시 바가 아래로 슬라이드되어 숨고, 위로 올리면 스프링으로 복귀.
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _navVisible,
        builder: (context, shown, child) => AnimatedSlide(
          offset: shown ? Offset.zero : const Offset(0, 1),
          duration: MotionDurations.base,
          curve: SpringCurve.standard,
          child: child,
        ),
        child: SpringyNavBar(
          currentIndex: _index,
          onTap: _select,
          items: _navItems,
        ),
      ),
    );
  }
}
