import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../models/chat.dart';
import '../motion/motion.dart';
import '../services/report_repository.dart';
import '../services/storage_service.dart';
import '../state/chat_room_state.dart';
import '../theme/app_palette.dart';
import '../utils/labels.dart' show timeAgo;
import '../widgets/overlay_icon_button.dart';
import '../widgets/report_sheet.dart';
import 'user_profile_screen.dart';

/// 채팅방 — 메시지 목록(실데이터) + 전송 + 실시간 수신.
class ChatRoomScreen extends StatefulWidget {
  final ChatRoomSummary room;

  /// 채팅 목록 타일에서 펼쳐지고/아래로 당기면 타일로 축소되는 인터랙션용. null 이면 일반 화면.
  final Rect? originRect;

  const ChatRoomScreen({super.key, required this.room, this.originRect});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with SingleTickerProviderStateMixin {
  // 상태·전송·실시간 구독은 홀더가 갖고, 화면은 구독해 그리기 + 확인 다이얼로그/
  // 토스트/스크롤/전환 모션만 담당한다 (docs/architecture-state.md).
  late final ChatRoomState _state = ChatRoomState(room: widget.room)
    ..onNewMessage = _scrollToBottom;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  // 축소 드래그 핸들 = 헤더(프로필 바) 영역. 메시지 스크롤과 당김이 겹치지 않도록
  // 축소는 헤더를 잡아 내릴 때만 시작한다.
  final _headerKey = GlobalKey();

  bool _inHeader(Offset global) {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  // 프로필 확장 전환용 — 헤더 바(패딩 제외) 위치 캡처 + 열린 동안 원본 숨김.
  final _profileBarKey = GlobalKey();
  bool _profileOpen = false;

  /// 축소 안착 시 크로스페이드될 헤더 바 모습(원본과 동일한 그림).
  Widget _headerBarCard() {
    final hasPhoto =
        _state.otherImageUrl != null || widget.room.otherNickname == '고객센터';
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ChatBlurBg(
            imageUrl: _state.otherImageUrl,
            nickname: widget.room.otherNickname,
          ),
          _ChatBarForeground(room: widget.room, hasPhoto: hasPhoto, m: 0),
        ],
      ),
    );
  }

  /// 헤더(프로필 바) 탭 → 상대 프로필이 바 자리에서 펼쳐지고, 당기면 그 자리로
  /// 축소된다(사용자 검색 타일 → 프로필과 동일한 전환).
  Future<void> _openOtherProfile() async {
    final uid = widget.room.otherUserId;
    if (uid == null) return; // 고객센터/알 수 없음
    final box = _profileBarKey.currentContext?.findRenderObject() as RenderBox?;
    final rect = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final page = UserProfileScreen(
      userId: uid,
      previewNickname: widget.room.otherNickname,
      originRect: rect,
      cardBuilder: rect == null ? null : (_) => _headerBarCard(),
      cardRadius: 16, // 헤더 바 곡률과 동일
      // 개인 대화방에서 연 프로필은 개인 얼굴 고정 — 업체 문의 방에서만 업체 얼굴
      // (어떤 사용자가 어떤 업체를 운영하는지 연결 차단, 0025)
      forcePersonalFace: !widget.room.isBusinessInquiry,
      // 프로필의 채팅 버튼이 이 방을 다시 쌓지 않고 되돌아오게(무한 왕복 방지).
      fromChatRoom: true,
    );
    if (rect != null) setState(() => _profileOpen = true);
    await Navigator.push(
      context,
      rect == null
          ? AppPageRoute(builder: (_) => page)
          : CollapseRoute(builder: (_) => page),
    );
    if (mounted) setState(() => _profileOpen = false);
  }

  // 2단계 축소 모션: 축소 완료 후 방 프로필 카드(0) → 목록 타일(1)로 변형.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  // 텍스트 이동이 뚝뚝 끊기지 않도록 감속 이징(선형 forward 대신).
  late final CurvedAnimation _morphCurved = CurvedAnimation(
    parent: _morph,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    _morphCurved.dispose();
    _morph.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 내 메시지 길게 누르기 → 삭제(소프트). 상대 메시지는 삭제 불가(신고만).
  Future<void> _deleteMyMessage(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('메시지를 삭제할까요?'),
        content: const Text('상대방 화면에서도 사라져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('삭제', style: TextStyle(color: dialogCtx.colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _state.deleteMyMessage(m.id)) _toast('삭제에 실패했어요');
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _state.sending) return;
    final err = await _state.send(text);
    if (!mounted) return;
    if (err != null) {
      _toast(err);
      return;
    }
    _ctrl.clear();
  }

  /// 사진 첨부 — 갤러리에서 선택해 업로드 후 사진 메시지로 전송.
  Future<void> _sendImage() async {
    if (_state.sending) return;
    final file = await StorageService.instance.pickImage();
    if (file == null || !mounted) return;
    final err = await _state.sendImage(file);
    if (err != null) _toast(err);
  }

  /// 채팅방 나가기 — 확인 후 목록에서 숨기고 방을 닫는다.
  Future<void> _leaveRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text(
          '나가면 채팅 목록에서 사라지고,\n'
          '서로 새 메시지를 보낼 수 없어요.\n'
          '내가 다시 채팅을 시작하면 대화가 이어져요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: context.colors.danger),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await _state.leaveRoom()) {
      if (mounted) Navigator.of(context).pop();
    } else {
      _toast('나가기에 실패했어요. 잠시 후 다시 시도해주세요');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 상단 메뉴 — 사용자 신고 / 채팅방 나가기.
  void _openRoomMenu() {
    final otherId = widget.room.otherUserId;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (otherId != null)
              ListTile(
                leading: Icon(
                  Icons.flag_outlined,
                  color: context.colors.danger,
                ),
                title: const Text('사용자 신고'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _report(
                    ReportRepository.targetUser,
                    otherId,
                    '사용자',
                    widget.room.otherNickname,
                  );
                },
              ),
            ListTile(
              leading: Icon(
                Icons.logout_outlined,
                color: context.colors.danger,
              ),
              title: const Text('채팅방 나가기'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _leaveRoom();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 상대 메시지 길게 누르기 — 해당 메시지 신고.
  void _reportMessage(ChatMessage msg) {
    _report(ReportRepository.targetChatMessage, msg.id, '메시지', msg.content);
  }

  Future<void> _report(
    String type,
    String id,
    String label,
    String title,
  ) async {
    final ok = await showReportSheet(
      context,
      targetType: type,
      targetId: id,
      targetLabel: label,
      targetTitle: title,
    );
    if (ok && mounted) _toast('신고가 접수되었어요. 검토 후 조치할게요');
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos =
          _scroll.position.minScrollExtent; // reverse:true → 0.0 이 맨 아래(최신)
      if (animate) {
        _scroll.animateTo(
          pos,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(pos);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 헤더 바가 상태바 아래에 떠 있고 상태바 뒤로는 메시지 영역 배경이 비치므로
    // 아이콘은 배경 밝기에 맞춘다 — 라이트에선 어둡게(무사진 방에서 흰 아이콘이
    // 안 보이던 문제 방지), 다크에선 밝게(검정 아이콘이 안 보이던 문제 방지).
    // 타일에서 펼쳐지고/아래로 당기면 타일로 축소되는 공통 래퍼(게시글 상세와 동일 언어).
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: CollapsibleView(
        originRect: widget.originRect,
        cardRadius: 16, // 채팅 목록 타일과 동일 곡률 — 안착 시 곡률 튐 방지.
        // 축소 도착 지점의 카드 = 방 프로필(m=0). 목록 타일이 아니라 방 헤더 모습이라
        // 축소 중 목록 타일이 비쳐 겹치는 투명 트렌지션이 생기지 않는다.
        card: (ctx) => _MorphCard(
          room: widget.room,
          imageUrl: _state.otherImageUrl,
          morph: _morphCurved,
          // 고객센터 방은 메뉴(신고·나가기) 없음 — 나갈 수 없는 상시 채널.
          onMenu: widget.room.isSupport ? null : _openRoomMenu,
        ),
        // 2단계: 축소가 타일 위치에 안착하면 방 프로필 → 목록 타일로 변형 후 pop.
        onSettled: () => _morph.forward(),
        // 축소는 헤더(프로필 바)를 잡아 내릴 때만 — 메시지 스크롤과 충돌 방지.
        dragHandleTest: _inHeader,
        scrollController: _scroll,
        // 채팅 목록 타일에서 확장되는 느낌을 강조 — 살짝 튕기며 열리고 시간도 조금 길게.
        expandDuration: const Duration(milliseconds: 520),
        expandCurve: Curves.easeOutBack,
        builder: (context, physics) => ListenableBuilder(
          listenable: _state,
          builder: (context, _) => Scaffold(
            backgroundColor: context.colors.background,
            body: Stack(
              children: [
                // 메시지 — 헤더 바 위(상태바 영역)와 입력창 아래(홈 인디케이터)까지
                // 풀블리드로 확장되어, 오버레이 패널 뒤로 비치며 스크롤된다
                // (탭 화면들의 플로팅 패널과 동일한 문법).
                Positioned.fill(child: _buildMessages(physics)),
                // 헤더 바 — 위 오버레이(블러 배경이라 뒤 메시지가 비친다).
                // 이 영역이 축소 드래그 핸들이다(_inHeader).
                Align(
                  alignment: Alignment.topCenter,
                  child: KeyedSubtree(
                    key: _headerKey,
                    child: _ChatHeader(
                      room: widget.room,
                      imageUrl: _state.otherImageUrl,
                      // 고객센터 방은 메뉴(신고·나가기) 없음 — 나갈 수 없는 상시 채널.
                      onMenu: widget.room.isSupport ? null : _openRoomMenu,
                      onProfileTap: widget.room.otherUserId == null
                          ? null
                          : _openOtherProfile,
                      barKey: _profileBarKey,
                      barHidden: _profileOpen,
                    ),
                  ),
                ),
                // 입력창 — 아래 오버레이. 상대가 나간 방은 입력을 잠근다(서버도 INSERT 차단).
                Align(
                  alignment: Alignment.bottomCenter,
                  child: widget.room.otherLeft
                      ? const _LockedBar()
                      : _Composer(
                          controller: _ctrl,
                          sending: _state.sending,
                          onSend: _send,
                          onPickImage: _sendImage,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(ScrollPhysics physics) {
    if (_state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final messages = _state.messages;
    if (messages.isEmpty) {
      return Center(
        child: Text(
          '첫 메시지를 보내보세요',
          style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
        ),
      );
    }
    // reverse:true — 최신 메시지를 맨 아래에 두고 그 위치에서 렌더 시작(진입 시 점프 없음).
    // 데이터는 오래된→최신 순이라, 표시 인덱스는 뒤에서부터 읽는다.
    // 패딩 — 평소엔 헤더 바 아래/입력창 위에서 시작·끝나되, 스크롤하면 그 뒤로
    // 지나가며 비친다(리스트 자체는 풀블리드).
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ListView.builder(
      controller: _scroll,
      physics: physics, // 드래그 중 잠금은 CollapsibleView 가 제공
      reverse: true,
      padding: EdgeInsets.fromLTRB(
        16,
        topInset + 8 + 72 + 16, // 상태바 + 헤더 바(72) + 간격
        16,
        bottomInset + 90, // 입력창(≈78) + 간격
      ),
      itemCount: messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: messages[messages.length - 1 - i],
        onReport: _reportMessage,
        onDeleteMine: _deleteMyMessage,
      ),
    );
  }
}

/// 채팅방 상단 히어로 헤더 — 채팅 목록 타일과 같은 크기·곡률·블러 배경의 방 프로필
/// 바(중앙 닉네임 + 메뉴). 축소가 끝나면 이 모습 그대로 타일 위치에 안착하고,
/// 그 뒤 [_MorphCard] 가 목록 타일 모습으로 변형한다(2단계).
class _ChatHeader extends StatelessWidget {
  final ChatRoomSummary room;
  final String? imageUrl;
  final VoidCallback? onMenu;

  /// 헤더(프로필 바) 탭 → 상대 프로필 상세. null 이면 탭 없음(고객센터 등).
  final VoidCallback? onProfileTap;

  /// 바(패딩 제외) 위치 캡처용 — 프로필 확장 전환의 originRect.
  final GlobalKey? barKey;

  /// 프로필이 열려 있는 동안 바를 빈자리로(축소가 겹침 없이 안착).
  final bool barHidden;

  const _ChatHeader({
    required this.room,
    required this.imageUrl,
    this.onMenu,
    this.onProfileTap,
    this.barKey,
    this.barHidden = false,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final hasPhoto = imageUrl != null || room.otherNickname == '고객센터';
    // 상태바 아래에 떠 있는 둥근(채팅 목록 타일과 동일한 16) 직사각형 바.
    // 좌우 여백 20, 높이 72(상하패딩16+2줄) — 목록 타일과 동일 크기.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 8, 20, 6),
      child: SizedBox(
        height: 72,
        child: Opacity(
          opacity: barHidden ? 0.0 : 1.0,
          child: KeyedSubtree(
            key: barKey,
            child: GestureDetector(
              // 탭 = 상대 프로필. 아래로 당기는 축소 드래그(raw pointer)와는 별개라 공존.
              onTap: onProfileTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ChatBlurBg(
                      imageUrl: imageUrl,
                      nickname: room.otherNickname,
                    ),
                    // 방 프로필 모습(m=0) — 축소 중엔 변형하지 않음.
                    _ChatBarForeground(
                      room: room,
                      hasPhoto: hasPhoto,
                      m: 0,
                      onMenu: onMenu,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 블러 배경(정적) — 프로필 사진 블러, 없으면 primaryDark. 애니메이션과 분리해
/// [_MorphCard] 에서 RepaintBoundary 로 캐시하면 변형 중 매 프레임 재블러를 피한다.
class _ChatBlurBg extends StatelessWidget {
  final String? imageUrl;
  final String nickname;
  const _ChatBlurBg({required this.imageUrl, required this.nickname});

  @override
  Widget build(BuildContext context) {
    // 고객센터는 전용 번들 이미지를 프로필처럼 사용.
    // cacheWidth 400 — 목록 타일(_ChatRoomTile)과 동일하게 맞춰 변형 종료 시
    // 블러 배경 질감이 어긋나지 않게 한다.
    final Widget? photoImage = imageUrl != null
        ? Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            cacheWidth: 400,
            errorBuilder: (_, _, _) =>
                ColoredBox(color: context.colors.primaryDark),
          )
        : (nickname == '고객센터'
              ? Image.asset(
                  'assets/images/cs_profile.png',
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                )
              : null);
    if (photoImage == null) {
      return ColoredBox(color: context.colors.primaryDark);
    }
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: 18, // 채팅 목록 타일과 동일한 블러 강도
        sigmaY: 18,
        tileMode: ui.TileMode.clamp,
      ),
      child: photoImage,
    );
  }
}

/// 바 전경 — 방 프로필(m=0) ↔ 목록 타일(m=1) 사이를 보간해 그린다. 스크림(어두움↔밝음),
/// 닉네임(중앙↔상단·흰↔검정, 크기는 Transform.scale 로 부드럽게), 메뉴(m=0에서만),
/// 마지막 메시지·시각(m=1에서 페이드 인). 방 헤더와 변형 카드가 같은 그림을 공유한다.
class _ChatBarForeground extends StatelessWidget {
  final ChatRoomSummary room;
  final bool hasPhoto;
  final double m; // 0=방 프로필, 1=목록 타일
  final VoidCallback? onMenu;
  const _ChatBarForeground({
    required this.room,
    required this.hasPhoto,
    required this.m,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final t = m.clamp(0.0, 1.0);
    // 크기(18↔15)는 fontSize 대신 Transform.scale 로 — fontSize 를 매 프레임 바꾸면
    // 텍스트 재레이아웃으로 글리프가 정수 픽셀에 스냅돼 덜덜거린다. base 는 타일과
    // 동일한 15px/w700 로 두고 스케일 1.2→1.0 을 줘서 m=1 에서 native 15px(=타일과
    // 완전히 동일·또렷)가 되게 한다 → pop 시 굵기/선명도 튐 없음.
    final nameScale = ui.lerpDouble(18.0 / 15.0, 1.0, t)!;
    final nameColor = hasPhoto
        ? Color.lerp(Colors.white, context.colors.textPrimary, t)!
        : context.colors.textOnPrimary;
    // 스크림: 방(어두움) → 타일(밝음). 사진 없으면 스크림 없음(primaryDark 유지).
    final scrim = hasPhoto
        ? Color.lerp(const Color(0x33000000), context.colors.photoVeil, t)!
        : null;
    final msg = room.lastMessage.isEmpty ? '대화를 시작해보세요' : room.lastMessage;
    final msgColor = hasPhoto ? context.colors.textSecondary : Colors.white70;
    final timeColor = hasPhoto ? context.colors.textTertiary : Colors.white70;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (scrim != null) Positioned.fill(child: ColoredBox(color: scrim)),
        // 닉네임+메시지 — m=0(방): 메시지 높이 0으로 접혀 닉네임만 세로 중앙.
        // m=1(타일): 상단 정렬(top16)로 닉네임 위 + 메시지 아래(타일과 동일 위치).
        // 축소되며 정렬이 중앙→상단으로 이동하고 메시지가 아래로 펼쳐지며(heightFactor)
        // 페이드 인 → 닉네임이 위로 이동하는 거리가 길어져 뚝 끊기지 않는다.
        Positioned.fill(
          child: Align(
            alignment: Alignment.lerp(
              Alignment.center,
              Alignment.topCenter,
              t,
            )!,
            child: Padding(
              padding: EdgeInsets.only(top: 16.0 * t),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 84),
                    child: Transform.scale(
                      scale: nameScale,
                      child: Text(
                        room.otherNickname,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ).copyWith(color: nameColor),
                      ),
                    ),
                  ),
                  // 메시지 — 아래로 펼쳐지며(높이 0→전체) 페이드 인.
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: t,
                      child: Opacity(
                        opacity: t,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: 4,
                            left: 60,
                            right: 60,
                          ),
                          child: Text(
                            msg,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: msgColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 시각 — 우측 상단(타일과 동일 위치: 상하16·좌우12 패딩 기준), 페이드 인.
        if (t > 0.01 && room.lastMessageAt != null)
          Positioned(
            top: 16,
            right: 12,
            child: Opacity(
              opacity: t,
              child: Text(
                timeAgo(room.lastMessageAt!),
                style: TextStyle(fontSize: 11, color: timeColor),
              ),
            ),
          ),
        // 메뉴 버튼 — 방 프로필(m=0)에서만, 타일화하며 페이드 아웃.
        if (t < 0.99 && onMenu != null)
          Positioned(
            top: 0,
            bottom: 0,
            right: 4,
            child: Opacity(
              opacity: 1 - t,
              child: IgnorePointer(
                ignoring: t > 0.01,
                child: OverlayIconButton(
                  icon: Icons.more_horiz,
                  tooltip: '메뉴',
                  onPressed: onMenu!,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 축소가 안착하는 타일 위치의 카드 — 방 프로필(m=0)로 시작해 [morph] 0→1 재생 시
/// 목록 타일(m=1) 모습으로 변형된다(2단계 애니메이션). 축소 도착점이 목록 타일이
/// 아니라 방 헤더라, 축소 중 목록 타일이 비쳐 겹치는 투명 트렌지션이 없다.
/// 블러 배경은 정적이라 RepaintBoundary 로 캐시하고, 전경만 morph 로 다시 그린다.
class _MorphCard extends StatelessWidget {
  final ChatRoomSummary room;
  final String? imageUrl;
  final Animation<double> morph;
  final VoidCallback? onMenu;
  const _MorphCard({
    required this.room,
    required this.imageUrl,
    required this.morph,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = imageUrl != null || room.otherNickname == '고객센터';
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 정적 블러 배경 — 캐시해 변형 중 매 프레임 재블러 방지.
          RepaintBoundary(
            child: _ChatBlurBg(
              imageUrl: imageUrl,
              nickname: room.otherNickname,
            ),
          ),
          // 전경만 morph(이징된 CurvedAnimation) 진행도로 다시 그린다.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: morph,
              builder: (context, _) => _ChatBarForeground(
                room: room,
                hasPhoto: hasPhoto,
                m: morph.value,
                onMenu: onMenu,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 상대가 나간 방의 잠긴 입력줄 — 안내만 표시.
class _LockedBar extends StatelessWidget {
  const _LockedBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          // 흰색 셀로판지 — 뒤로 지나가는 메시지가 비친다(입력창과 동일).
          color: context.colors.frostFilm,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.block_outlined,
              size: 15,
              color: context.colors.textTertiary,
            ),
            SizedBox(width: 6),
            Text(
              '상대가 채팅방을 나가 메시지를 보낼 수 없어요',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          // 흰색 셀로판지 — 뒤로 지나가는 메시지가 비친다(상단 헤더·탭 패널과 동일).
          color: context.colors.frostFilm,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(
                Icons.add_photo_alternate_outlined,
                color: context.colors.primaryDark,
              ),
              onPressed: sending ? null : onPickImage,
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: '메시지를 입력하세요',
                    filled: true,
                    fillColor: context.colors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide(
                        color: context.colors.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: BoxDecoration(
                color: context.colors.primaryDark,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: sending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.textOnPrimary,
                        ),
                      )
                    : Icon(
                        Icons.arrow_upward,
                        color: context.colors.textOnPrimary,
                      ),
                onPressed: sending ? null : onSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// 상대 메시지 길게 누르기 신고 콜백.
  final void Function(ChatMessage) onReport;

  /// 내 메시지 길게 누르기 → 삭제(본인 것만 — 상대 메시지는 신고만 가능).
  final void Function(ChatMessage) onDeleteMine;

  const _MessageBubble({
    required this.message,
    required this.onReport,
    required this.onDeleteMine,
  });

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final at = message.createdAt;
    final timeStr =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: context.colors.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: GestureDetector(
              // 길게 누르기: 내 메시지 = 삭제, 상대 메시지 = 신고.
              onLongPress: mine
                  ? () => onDeleteMine(message)
                  : () => onReport(message),
              onTap: message.isImage ? () => _openImage(context) : null,
              child: message.isImage ? _imageBody() : _textBody(context, mine),
            ),
          ),
          if (!mine) ...[
            const SizedBox(width: 6),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 텍스트 버블.
  Widget _textBody(BuildContext context, bool mine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? context.colors.primaryDark : context.colors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
        border: Border.all(
          color: mine ? context.colors.primaryDark : context.colors.border,
          width: 0.5,
        ),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          color: mine
              ? context.colors.textOnPrimary
              : context.colors.textPrimary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  /// 사진 메시지 — 버블 배경 없이 라운드 이미지만(카카오식). 탭하면 크게 보기.
  Widget _imageBody() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280),
        child: Image.network(
          message.imageUrl!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : Container(
                  width: 200,
                  height: 200,
                  color: context.colors.surfaceMuted,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
          errorBuilder: (context, _, _) => Container(
            width: 200,
            height: 140,
            color: context.colors.surfaceMuted,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 전체화면 사진 보기 — 핀치 줌, 탭/뒤로가기로 닫기.
  void _openImage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Image.network(message.imageUrl!, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}
