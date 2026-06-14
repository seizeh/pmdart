import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// PawMate 모션 시스템 — Physics-based / Fluid Motion 의 단일 출처(single source of truth).
///
/// 앱 전체가 같은 스프링 물리를 공유하도록 토큰을 한곳에 모은다.
/// 같은 물리를 공유한다는 것 자체가 **연속성(continuity)** 의 토대가 된다:
/// 카드를 누를 때, 화면이 전환될 때, 탭이 바뀔 때 모두 "같은 재질감"으로 움직인다.
///
/// 4가지 원칙이 이 토큰들로 표현된다.
/// - continuity : 모든 전환이 [MotionSprings] 의 동일한 곡선을 공유
/// - hierarchy  : [MotionStagger] 로 부모→자식 등장 순서를 통제
/// - feedback   : [MotionSprings.press] / [MotionSprings.bounce] 로 즉각 반응
/// - direction  : 스프링은 속도(velocity)를 이어받으므로 제스처 방향/관성이 유지됨
class MotionDurations {
  MotionDurations._();

  /// 가벼운 마이크로 인터랙션(아이콘 바운스 등).
  static const Duration micro = Duration(milliseconds: 220);

  /// 카드 등장, 탭 전환 같은 기본 전환.
  static const Duration base = Duration(milliseconds: 420);

  /// 화면 전환처럼 공간을 가로지르는 큰 모션.
  static const Duration page = Duration(milliseconds: 520);
}

/// 스프링 프리셋. 댐핑비(ratio)로 "출렁임"의 성격을 정의한다.
/// - ratio 1.0  → 오버슈트 없이 부드럽게 안착(임계 감쇠)
/// - ratio <1.0 → 살짝 튕기며 안착(언더 댐핑) = 더 살아있는 느낌
class MotionSprings {
  MotionSprings._();

  /// 표준 전환: 거의 임계 감쇠라 미세한 오버슈트만 — 차분하고 고급스러움.
  static final SpringDescription standard = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 170,
    ratio: 0.9,
  );

  /// 살아있는 등장/전환: 작은 오버슈트로 생동감.
  static final SpringDescription lively = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 210,
    ratio: 0.78,
  );

  /// 누르는 즉시 단단히 잡히는 느낌(피드백 down).
  static final SpringDescription press = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 560,
    ratio: 1.0,
  );

  /// 손을 떼면 탄력적으로 되돌아오는 느낌(피드백 release).
  static final SpringDescription bounce = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.52,
  );
}

/// 위계(hierarchy)를 만드는 stagger 간격.
class MotionStagger {
  MotionStagger._();

  /// 리스트 아이템 사이의 등장 지연 단위.
  static const Duration step = Duration(milliseconds: 55);

  /// 너무 긴 리스트가 끝없이 지연되지 않도록 상한.
  static const int maxSteps = 8;

  static Duration delayFor(int index) =>
      step * (index.clamp(0, maxSteps)).toDouble();
}

/// [SpringSimulation] 을 [0,1] 구간의 [Curve] 로 감싼다.
///
/// Flutter 기본 곡선에는 진짜 스프링이 없다. 이 곡선은 실제 스프링 시뮬레이션을
/// 시간 정규화하여, 어떤 [AnimationController] duration 과도 함께 쓰면서
/// 오버슈트(출렁임)를 그대로 살린다. → 모든 트윈이 같은 물리를 공유(continuity).
class SpringCurve extends Curve {
  SpringCurve({
    double mass = 1,
    double stiffness = 170,
    double ratio = 0.82,
    double velocity = 0,
  }) : _sim = SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: mass,
            stiffness: stiffness,
            ratio: ratio,
          ),
          0,
          1,
          velocity,
        ) {
    // 스프링이 안착하는 데 걸리는 시간을 추정해 [0,1] 로 정규화한다.
    double t = 0;
    const stepSize = 1 / 240;
    while (t < 4 && !_sim.isDone(t)) {
      t += stepSize;
    }
    _settle = t <= 0 ? 1 : t;
  }

  final SpringSimulation _sim;
  late final double _settle;

  /// 표준 프리셋 — 차분하게 안착.
  static final SpringCurve standard = SpringCurve(stiffness: 170, ratio: 0.9);

  /// 생동감 프리셋 — 살짝 튕김.
  static final SpringCurve lively = SpringCurve(stiffness: 210, ratio: 0.72);

  /// 스냅 프리셋 — 오버슈트 없이 빠르게 안착. 화면 전환처럼 즉각 반응해야 할 때.
  static final SpringCurve snappy = SpringCurve(stiffness: 320, ratio: 1.0);

  @override
  double transformInternal(double t) => _sim.x(t * _settle);
}

/// 자주 쓰는 보조: 컨트롤러 현재 값/속도를 이어받아 스프링으로 목표까지 보낸다.
/// 속도가 이어지므로 제스처의 **방향과 관성**이 끊기지 않는다(direction).
extension SpringAnimate on AnimationController {
  TickerFuture springTo(
    double target, {
    required SpringDescription spring,
    double? from,
  }) {
    if (from != null) value = from;
    return animateWith(SpringSimulation(spring, value, target, velocity));
  }
}
