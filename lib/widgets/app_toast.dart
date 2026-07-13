import 'dart:async';
import 'package:flutter/material.dart';

/// 하단 알림 로그 토스트.
///
/// - 등장: 아래에서 위로 살짝 튕기며(easeOutBack 오버슛) 올라와 플로팅 하단
///   메뉴바 위에 안착한다.
/// - 퇴장: 다시 아래로 내려가며 사라진다. 클립 경계를 메뉴바 상단에 맞춰,
///   내려가는 토스트가 메뉴바 뒤로 잠기듯 자연스럽게 사라진다.
///
/// SnackBar 는 퇴장이 페이드(불투명도)라 이 모션을 낼 수 없어 오버레이로 직접
/// 구현한다. 호출: `AppToast.show(navigatorKey.currentState!.overlay!, '메시지')`.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;

  static void show(OverlayState overlay, String message) {
    // 이전 토스트는 즉시 교체(겹침 방지).
    _entry?.remove();
    _entry = null;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        onDone: () {
          if (_entry == entry) _entry = null;
          entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  const _ToastWidget({required this.message, required this.onDone});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
    reverseDuration: const Duration(milliseconds: 320),
  );

  // 등장은 튕김(오버슛), 퇴장은 가속하며 아래로.
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(const Duration(milliseconds: 2800), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // 플로팅 하단 메뉴바(높이 62 + 아래 여백 bottomInset+8)의 상단 = 클립 하단 경계.
    // 이 경계 아래로 내려간 부분은 그려지지 않아 "메뉴바 뒤로 사라지는" 그림이 된다.
    final navTop = bottomInset + 8 + 62;

    return Positioned(
      left: 12,
      right: 12,
      bottom: navTop,
      child: IgnorePointer(
        child: ClipRect(
          child: Padding(
            // top: 튕김 오버슛 여유 / bottom: 메뉴바 위 안착 간격.
            padding: const EdgeInsets.only(top: 12, bottom: 10),
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, child) => FractionalTranslation(
                // t=1 안착(0), t=0 클립 아래로 완전히 잠김(+1.4배 높이).
                translation: Offset(0, (1 - _t.value) * 1.4),
                child: child,
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: scheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
