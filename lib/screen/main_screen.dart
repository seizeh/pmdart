import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../services/care_report_repository.dart';
import '../services/keyboard_barrier.dart';
import '../theme/app_palette.dart';
import '../utils/layout.dart';
import '../widgets/app_shell.dart';
import 'tabs/chat_tab.dart';
import 'tabs/community_tab.dart';
import 'tabs/map_tab.dart';
import 'tabs/my_info_tab.dart';
import 'tabs/user_search_tab.dart';

/// 메인 화면 — 바텀 네비게이션.
/// 탭 순서: 지도(개발중) / 사용자검색 / 커뮤니티(중앙=기본) / 채팅 / 내정보
/// 기본 진입 탭은 커뮤니티.
///
/// 웹은 지도·채팅을 뺀 3탭이다(docs/web-port.md) — 아래 `tabMap`… 상수는 위치가
/// 아니라 **탭 정체성**이므로 플랫폼과 무관하게 고정이다. 실제 표시 순서는
/// `visibleTabs` 가 정하고, 딥링크는 상수로 요청하면 알아서 매핑된다.
class MainScreen extends StatefulWidget {
  final bool isGuest;
  const MainScreen({super.key, this.isGuest = false});

  /// 외부(푸시 딥링크 등)에서의 탭 전환 요청 — 아래 탭 상수를 넣으면 화면이 전환 후
  /// null 로 리셋한다. 딥링크가 상세를 얹기 전에 "뒤로 갔을 때 보일 탭"을 맞출 때 사용.
  /// 현재 플랫폼에 없는 탭(웹의 지도·채팅)을 요청하면 무시된다.
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  static const tabMap = 0,
      tabSearch = 1,
      tabCommunity = 2,
      tabChat = 3,
      tabMyInfo = 4;

  /// 이 플랫폼에서 실제로 노출하는 탭 — 표시 순서대로.
  static const List<int> visibleTabs = kIsWeb
      ? [tabSearch, tabCommunity, tabMyInfo]
      : [tabMap, tabSearch, tabCommunity, tabChat, tabMyInfo];

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  // `_index` 는 `MainScreen.visibleTabs` 안에서의 위치다(탭 상수와 다름).
  int _index = MainScreen.visibleTabs.indexOf(MainScreen.tabCommunity);
  int _direction = 0; // 마지막 탭 이동 방향(+1 오른쪽, -1 왼쪽)

  /// 현재 보고 있는 탭의 정체성 상수.
  int get _currentTab => MainScreen.visibleTabs[_index];

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

  // 노출하는 탭만 생성한다 — 웹에서 MapTab 을 만들면 웹 구현이 없는 지도
  // 플랫폼뷰가 붙는다.
  late final List<Widget> _tabs = [
    for (final t in MainScreen.visibleTabs) _buildTab(t),
  ];

  Widget _buildTab(int tab) => switch (tab) {
    MainScreen.tabMap => const MapTab(),
    MainScreen.tabSearch => const UserSearchTab(),
    MainScreen.tabCommunity => CommunityTab(
      isGuest: widget.isGuest,
      chromeVisible: _navVisible,
    ),
    MainScreen.tabChat => ChatTab(isGuest: widget.isGuest),
    _ => MyInfoTab(isGuest: widget.isGuest, chromeVisible: _navVisible),
  };

  // 라벨 없는 아이콘 단독 내비 — 앱의 둥근 무드에 맞춘 rounded 계열로 통일
  // (외곽선 아이콘은 각져 보여 제외). 활성/비활성 구분은 색·확대·알약이 담당.
  static const _navIcons = {
    MainScreen.tabMap: Icons.location_on_rounded, // 지도 — 둥근 핀
    MainScreen.tabSearch: Icons.person_search_rounded, // 검색
    MainScreen.tabCommunity: Icons.groups_rounded, // 커뮤니티 — 지붕 없는 둥근 형태
    MainScreen.tabChat: Icons.chat_bubble_rounded, // 채팅
    MainScreen.tabMyInfo: Icons.person_rounded, // 내정보
  };

  static final _navItems = [
    for (final t in MainScreen.visibleTabs) SpringyNavItem(icon: _navIcons[t]!),
  ];

  @override
  void initState() {
    super.initState();
    _syncKeyboardBarrier();
    _publishRail();
    MainScreen.tabRequest.addListener(_onTabRequest);
    // 화면 생성 전에 들어온 요청(콜드 스타트 딥링크)은 첫 프레임 뒤에 소비.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTabRequest());
    // 케어 리포트 자동 연결(0028 §4.2) — 로그인 홈 진입마다 1회. 가입 직후·기존
    // 사용자 모두 커버하고, 연결되면 도착 알림은 서버가 발송한다. 실패 무해.
    CareReportRepository.instance.claim();
  }

  void _onTabRequest() {
    final tab = MainScreen.tabRequest.value;
    if (tab == null) return;
    MainScreen.tabRequest.value = null;
    // 이 플랫폼에 없는 탭(웹의 지도·채팅)이면 -1 → 무시.
    final i = MainScreen.visibleTabs.indexOf(tab);
    if (mounted && i >= 0) _select(i);
  }

  // 지도 탭은 자동완성 제안 탭을 위해 전역 키보드 배리어를 끈다.
  void _syncKeyboardBarrier() =>
      keyboardBarrierEnabled.value = _currentTab != MainScreen.tabMap;

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _direction = i > _index ? 1 : -1;
      _index = i;
    });
    _navVisible.value = true; // 탭 전환 시 바는 항상 보이게 복귀
    _syncKeyboardBarrier();
    _publishRail();
    _tab.forward(from: 0); // 새 탭이 방향에서 흘러 들어옴
  }

  @override
  void dispose() {
    MainScreen.tabRequest.removeListener(_onTabRequest);
    navRail.value = null; // 로그아웃 등으로 벗어나면 레일도 사라진다
    _tab.dispose();
    _navVisible.dispose();
    super.dispose();
  }

  /// 좌측 레일(넓은 화면)에 현재 탭 상태를 공개 — 그리는 것은 [AppShell] 이다.
  /// 레일이 본문 컬럼 **바깥**에 있어야 하고 상세 라우트 위에서도 유지돼야 해서
  /// 여기서 직접 그리지 않는다.
  void _publishRail() => navRail.value = NavRailConfig(
    currentIndex: _index,
    items: _navItems,
    onTap: _select,
  );

  /// 탭 본문 — 전환 시 방향에서 흘러 들어오는 모션 포함. 가로/세로 크롬 공용.
  Widget _body() => AnimatedBuilder(
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
    // IndexedStack 으로 각 탭 상태는 보존하고, 전환 순간에만 방향성 있게 흘려 보낸다.
    child: IndexedStack(index: _index, children: _tabs),
  );

  @override
  Widget build(BuildContext context) {
    // 넓은 화면(데스크톱 웹)은 하단 바 대신 좌측 레일 — 레일은 본문 컬럼 바깥에
    // 있어야 하므로 AppShell 이 그린다. 여기서는 하단 바만 뺀다.
    // 본문(카드·타이포·모션)은 폭과 무관하게 앱과 동일하다 — 바뀌는 건 크롬뿐.
    final sideNav = useSideNav(context);

    return Scaffold(
      backgroundColor: context.colors.background,
      // body 를 하단 바 뒤까지 확장 → 바가 숨을 때 콘텐츠가 화면 끝까지 차서
      // 흰 여백이 생기지 않는다(각 탭은 바 높이만큼 하단 패딩으로 가림 방지).
      extendBody: true,
      // 키보드 리사이즈 금지 — 켜두면 키보드가 오르내리는 매 프레임 IndexedStack 의
      // 5개 탭 전부(지도 플랫폼뷰 포함)가 재레이아웃돼 검색 중 스크롤이 심하게 끊긴다.
      // 탭 내 입력 필드(커뮤니티·사용자 검색)는 모두 상단이라 가려질 것이 없다.
      resizeToAvoidBottomInset: false,
      body: _body(),
      // 아래로 스크롤 시 바가 아래로 슬라이드되어 숨고, 위로 올리면 스프링으로 복귀.
      // 좌측 레일에서는 세로 공간을 두고 다툴 일이 없어 숨기지 않는다(항상 표시).
      bottomNavigationBar: sideNav
          ? null
          : ValueListenableBuilder<bool>(
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
