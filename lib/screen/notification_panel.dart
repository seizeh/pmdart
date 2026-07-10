import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show timeAgo;
import '../models/notification.dart';
import '../services/notification_repository.dart';
import '../services/community_repository.dart';
import '../services/chat_repository.dart';
import 'post_detail_screen.dart';
import 'chat_room_screen.dart';
import 'guardian_invites_screen.dart';

/// 알림 벨을 탭하면 그 자리에서 **아래로 확장되는 알림 패널**을 연다(Slack 채널 헤더가
/// 메뉴로 펼쳐지는 스펠 차용). 패널 높이는 알림 수에 비례해 커지고, 화면을 넘으면 스크롤.
/// [anchor] 는 벨의 화면상 사각형, [items] 는 **미리 로드한 알림 목록**(첫 프레임부터
/// 실제 크기로 확장되도록 벨이 먼저 받아 넘긴다 — 로딩 중 크기가 튀지 않게).
Future<void> showNotificationPanel(
  BuildContext context,
  Rect anchor,
  List<AppNotification> items,
) {
  return Navigator.of(
    context,
  ).push(_NotificationPanelRoute(anchor: anchor, items: items));
}

class _NotificationPanelRoute extends PopupRoute<void> {
  _NotificationPanelRoute({required this.anchor, required this.items});
  final Rect anchor;
  final List<AppNotification> items;

  @override
  Color? get barrierColor => null; // 스크림은 직접 그린다.

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '알림 닫기';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 720);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    // 패널 폭(우측 정렬) + 벨 옆 남은 공간에 맞춘 최대 높이.
    final panelW = math.min(screenW - 24.0, 380.0);
    final panelRight = (screenW - anchor.right).clamp(8.0, screenW - 8);
    final panelLeft = screenW - panelRight - panelW;
    final panelTop = anchor.top;
    final maxH = (media.size.height - panelTop - 12 - media.padding.bottom)
        .clamp(160.0, 640.0);

    // 3단계 순차: ① 패널이 벨(우측 상단) 코너에서 8시 방향(좌하)으로 클립 확장,
    //   ② 벨 아이콘(형태 그대로)이 우측(벨 자리)→좌측 상단으로 이동,
    //   ③ 도착하면 '알림' 제목과 '모두 읽음'이 페이드로 자연스럽게 나타난다.
    // 확장(①)에 시간을 넉넉히 배분해 8시 방향으로 펼쳐지는 과정이 잘 보이게 한다.
    final expand = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.62, curve: Curves.easeInOutCubic),
    );
    final slide = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.6, 0.85, curve: Curves.easeOutBack),
    );
    final reveal = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.85, 1.0, curve: Curves.easeOut),
    );
    // ④ 확장이 끝날 때 살짝 튕기는 마무리 — 벨 코너 기준 미세 오버슛 후 정착.
    final settle = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
    );

    // 벨 아이콘 시작(실제 벨 중심)·도착(헤더 좌측 상단 슬롯) — 크기/형태 동일.
    const bellR = 13.0; // 지름 26 (앱 헤더 벨과 동일)
    final bellStart = anchor.center;
    final bellEnd = Offset(panelLeft + 14 + bellR, panelTop + 12 + bellR);

    return Stack(
      children: [
        // 스크림 — 바깥 탭 → 닫기.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: FadeTransition(
              opacity: animation,
              child: const ColoredBox(color: Color(0x33000000)),
            ),
          ),
        ),
        // ① 패널 — 우측 상단 코너 고정, 코너에서 클립 확장(내용은 원래 크기라 안 찌그러짐).
        Positioned(
          top: panelTop,
          right: panelRight,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Opacity(
              // 거의 즉시 불투명 → 솔리드 박스가 8시 방향으로 커지는 게 또렷이 보임.
              opacity: (animation.value * 10).clamp(0.0, 1.0),
              // 확장 마무리에 벨 코너 기준으로 살짝 튕겼다가(1.5% 오버슛) 정착.
              child: Transform.scale(
                alignment: Alignment.topRight,
                scale: 0.95 + 0.05 * settle.value,
                // ClipRect 로 실제 잘라야 확장이 보인다(Align 만으론 자식이 안 잘림).
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topRight, // 벨 코너 기준으로 펼쳐짐
                    widthFactor: expand.value.clamp(0.0001, 1.0),
                    heightFactor: expand.value.clamp(0.0001, 1.0),
                    child: child,
                  ),
                ),
              ),
            ),
            child: SizedBox(
              width: panelW,
              child: _NotificationPanel(
                maxHeight: maxH,
                reveal: reveal,
                items: items,
              ),
            ),
          ),
        ),
        // ② 이동하는 벨 아이콘 — 확장 후 우측(벨)→좌측 상단으로 슬라이드.
        AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final c = Offset.lerp(
              bellStart,
              bellEnd,
              slide.value.clamp(0.0, 1.0),
            )!;
            return Positioned(
              left: c.dx - bellR,
              top: c.dy - bellR,
              width: bellR * 2,
              height: bellR * 2,
              child: Opacity(
                opacity: (animation.value * 4).clamp(0.0, 1.0), // 빠른 페이드인
                child: child,
              ),
            );
          },
          child: const _BellDot(),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child; // 애니메이션은 buildPage 내부에서 처리.
}

class _NotificationPanel extends StatefulWidget {
  const _NotificationPanel({
    required this.maxHeight,
    required this.reveal,
    required this.items,
  });
  final double maxHeight;
  final Animation<double> reveal; // '알림'·'모두 읽음' 등장(벨 도착 후).
  final List<AppNotification> items; // 미리 로드된 목록(첫 프레임부터 실제 크기).

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  final _repo = NotificationRepository.instance;
  late List<AppNotification> _items = List.of(widget.items);

  Future<void> _markAll() async {
    try {
      await _repo.deleteAll();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _items = [];
      });
    }
  }

  void _onTap(AppNotification n) {
    final nav = Navigator.of(context);
    _repo.delete(n.id); // 확인한 알림은 삭제
    nav.pop(); // 패널 닫기
    _navigate(nav, n);
  }

  Future<void> _navigate(NavigatorState nav, AppNotification n) async {
    if (n.type == 'guardian_invite') {
      nav.push(AppPageRoute(builder: (_) => const GuardianInvitesScreen()));
      return;
    }
    if (n.resourceId == null) return;
    try {
      if (n.resourceType == 'post') {
        final post = await CommunityRepository.instance.fetchPost(
          n.resourceId!,
        );
        if (post != null) {
          nav.push(AppPageRoute(builder: (_) => PostDetailScreen(post: post)));
        }
      } else if (n.resourceType == 'chat_room') {
        final room = await ChatRepository.instance.fetchRoom(n.resourceId!);
        if (room != null) {
          nav.push(AppPageRoute(builder: (_) => ChatRoomScreen(room: room)));
        }
      }
    } catch (_) {
      /* 이동 실패는 조용히 — 읽음 처리는 이미 됨 */
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Material(
      color: Colors.white,
      elevation: 12,
      borderRadius: BorderRadius.circular(18),
      // 내용(리스트)을 둥근 모서리로 클립 → 하단이 각지게 삐져나오지 않음.
      clipBehavior: Clip.antiAlias,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더 — 벨 안착 자리(이동 아이콘이 앉음) + 제목/모두읽음(도착 후 페이드 등장).
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    const SizedBox(width: 26, height: 26), // 벨 안착 자리
                    const SizedBox(width: 8),
                    FadeTransition(
                      opacity: widget.reveal,
                      child: const Text(
                        '알림',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // 모두 읽음 ↔ 닫기 — 누르면 같은 자리에서 부드럽게 교체.
                    FadeTransition(
                      opacity: widget.reveal,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: _items.isNotEmpty
                            ? TextButton(
                                key: const ValueKey('markAll'),
                                onPressed: _markAll,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '모두 읽음',
                                  style: TextStyle(fontSize: 13),
                                ),
                              )
                            // 알림이 없으면(처음부터 비었든 모두 읽음 후든) 닫기 버튼.
                            : TextButton(
                                key: const ValueKey('close'),
                                onPressed: () => Navigator.of(context).pop(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '닫기',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // 본문 — 빈 상태는 최대 높이의 1/3(컴팩트). 알림이 있으면 개수에 맞게
            // 늘어나되 최소 1/3·최대(현재 상태)까지, 넘으면 스크롤.
            if (items.isEmpty)
              SizedBox(
                height: widget.maxHeight / 3,
                child: const Center(
                  child: Text(
                    '받은 알림이 없어요',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: widget.maxHeight / 3),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) => _PanelTile(
                      notification: items[i],
                      onTap: () => _onTap(items[i]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 우측(벨 자리)→좌측 상단 헤더로 이동하는 벨 아이콘.
/// 앱 헤더의 벨과 동일한 형태(원형 배경 없는 아웃라인 아이콘) — 이동 중 디자인 불변.
class _BellDot extends StatelessWidget {
  const _BellDot();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.notifications_outlined,
        size: 26, // 앱 헤더 벨과 동일 크기
        color: AppColors.primaryDark,
      ),
    );
  }
}

/// 패널용 컴팩트 알림 행.
class _PanelTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  const _PanelTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.isRead
            ? Colors.white
            : AppColors.primarySoft.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(n.icon, size: 17, color: AppColors.primaryDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (n.body != null && n.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      n.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    timeAgo(n.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (!n.isRead)
              Container(
                margin: const EdgeInsets.only(top: 4, left: 6),
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
