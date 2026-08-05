/// PawMate 모션 시스템 배럴.
///
/// Physics-based / Fluid Motion 디자인을 4원칙으로 구현한다.
/// - continuity : [SpringCurve] 공유, [buildFluidTransition] 화면 전환
/// - hierarchy  : [Entrance] stagger 등장
/// - feedback   : [Pressable], [HeartButton], [SpringyNavBar]
/// - direction  : 스프링 velocity 승계(틸트·알약 이동·탭 슬라이드)
library;

export 'app_motion.dart';
export 'collapse_route.dart';
export 'entrance.dart';
export 'flying_card.dart';
export 'heart_burst.dart';
export 'pressable.dart';
export 'scroll_chrome.dart';
export 'spring_page_route.dart';
export 'springy_nav_bar.dart';
