import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

import 'app_motion.dart';

/// 아래로 스크롤하면 상단 헤더와 하단 네비 바가 함께 숨고, 위로 올리면 스프링으로
/// 돌아오는 규칙.
///
/// 커뮤니티·내정보에 각자 복사돼 있던 로직이다(임계값과 함께 숨길 대상만 달랐다).
/// 검색·채팅에도 같은 동작을 넣으면서 네 번째 복사본을 만드는 대신 여기로 모았다 —
/// 복사본은 갈라진다. **커뮤니티 탭은 아직 자기 것을 쓴다**: 거기서는 같은
/// 컨트롤러가 글쓰기 FAB 스프링을 겸해서 단순 치환이 아니다.
///
/// 쓰는 쪽은 셋만 하면 된다:
///   1. `NotificationListener<UserScrollNotification>(onNotification: chrome.onUserScroll, …)`
///   2. 헤더를 `AnimatedBuilder(animation: chrome, …)` 로 감싸고 `shift: chrome.hidden * H`
///   3. `dispose()` 에서 `chrome.dispose()`
class ScrollChrome extends ChangeNotifier {
  ScrollChrome({
    required TickerProvider vsync,
    this.chromeVisible,
    this.revealBelow = 64,
  }) {
    _ctrl = AnimationController.unbounded(vsync: vsync, value: 1)
      ..addListener(notifyListeners);
    chromeVisible?.addListener(_onExternalReveal);
  }

  /// 바깥에서 크롬을 되돌린 경우(탭 전환 등) 헤더도 같이 돌아온다.
  ///
  /// [chromeVisible] 은 MainScreen 소유고 탭을 바꿀 때마다 true 로 리셋된다.
  /// 이걸 듣지 않으면 숨은 채로 탭을 떠났다가 돌아왔을 때 **네비 바만 보이고
  /// 헤더는 숨어 있는** 상태가 된다(다시 스크롤할 때까지).
  /// true 만 따른다 — false 는 다른 탭이 스크롤해서 내린 것일 수 있다.
  void _onExternalReveal() {
    if (chromeVisible?.value == true) reveal();
  }

  late final AnimationController _ctrl;

  /// 하단 네비 바 표시 신호(MainScreen 소유). 헤더와 **같은 신호**로 움직여야
  /// 위아래가 따로 노는 일이 없다.
  final ValueNotifier<bool>? chromeVisible;

  /// 이 위치보다 위(상단 근처)에서는 항상 보인다 — 헤더가 밀려날 만큼 스크롤되기
  /// 전에 숨으면 그 자리가 빈 공간으로 남는다.
  final double revealBelow;

  /// 0 = 완전히 보임, 1 = 완전히 숨김. 헤더 `shift` 에 곱해 쓴다.
  double get hidden => 1 - _ctrl.value.clamp(0.0, 1.0);

  bool _shown = true;

  void _set(bool show, {required SpringDescription spring}) {
    if (_shown == show) return;
    _shown = show;
    _ctrl.springTo(show ? 1 : 0, spring: spring);
    chromeVisible?.value = show;
  }

  /// 즉시 보이게 되돌린다 — 탭 전환·목록 갱신처럼 스크롤과 무관하게 크롬이
  /// 돌아와야 하는 자리에서 부른다.
  void reveal() => _set(true, spring: MotionSprings.standard);

  /// `NotificationListener<UserScrollNotification>` 에 그대로 물린다.
  bool onUserScroll(UserScrollNotification n) {
    // 가로 스크롤(캐러셀 등)은 무시 — 세로 본문만 반응한다.
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.pixels < revealBelow) {
      _set(true, spring: MotionSprings.standard);
      return false;
    }
    if (n.direction == ScrollDirection.reverse) {
      _set(false, spring: MotionSprings.standard);
    } else if (n.direction == ScrollDirection.forward) {
      // 되돌아올 때만 탄력을 준다 — 숨을 때 튀면 산만하다.
      _set(true, spring: MotionSprings.bounce);
    }
    return false;
  }

  @override
  void dispose() {
    chromeVisible?.removeListener(_onExternalReveal);
    _ctrl.removeListener(notifyListeners);
    _ctrl.dispose();
    super.dispose();
  }
}
