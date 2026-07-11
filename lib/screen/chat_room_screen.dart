import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../models/chat.dart';
import '../services/chat_repository.dart';
import '../services/report_repository.dart';
import '../services/storage_service.dart';
import '../widgets/overlay_icon_button.dart';
import '../widgets/report_sheet.dart';

/// 채팅방 — 메시지 목록(실데이터) + 전송 + 실시간 수신.
class ChatRoomScreen extends StatefulWidget {
  final ChatRoomSummary room;

  /// 채팅 목록 타일에서 펼쳐지고/아래로 당기면 타일로 축소되는 인터랙션용. null 이면 일반 화면.
  final Rect? originRect;

  /// 축소 시 크로스페이드로 나타날 실제 채팅 타일(목록과 동일 위젯).
  final WidgetBuilder? cardBuilder;

  const ChatRoomScreen({
    super.key,
    required this.room,
    this.originRect,
    this.cardBuilder,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _repo = ChatRepository.instance;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;

  // 상대 프로필 사진(히어로 헤더용) — 없으면 닉네임 중앙 표시.
  late String? _otherImageUrl = widget.room.otherProfileImageUrl;

  Future<void> _loadOtherProfile() async {
    final uid = widget.room.otherUserId;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('public_profiles')
          .select('profile_image_url')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) {
        setState(() => _otherImageUrl = row?['profile_image_url'] as String?);
      }
    } catch (_) {/* 실패 시 무사진 헤더 유지 */}
  }

  @override
  void initState() {
    super.initState();
    _loadOtherProfile();
    _init();
  }

  Future<void> _init() async {
    try {
      final msgs = await _repo.fetchMessages(widget.room.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _markRead();
      // reverse:true 리스트라 첫 프레임부터 맨 아래(최신)에 고정 — 별도 스크롤 점프 불필요.
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
    // 실시간 구독 (상대 메시지 수신)
    try {
      _channel = _repo.subscribeMessages(widget.room.id, _onIncoming);
    } catch (_) {
      // 실시간 미동작 시에도 전송/로드는 정상.
    }
  }

  void _onIncoming(ChatMessage msg) {
    if (!mounted) return;
    if (_messages.any((m) => m.id == msg.id)) return; // 중복 방지
    setState(() => _messages.add(msg));
    if (!msg.mine) _markRead();
    _scrollToBottom();
  }

  void _markRead() {
    if (_messages.isEmpty) return;
    _repo.markRead(widget.room.id, _messages.last.id).catchError((_) {});
  }

  @override
  void dispose() {
    if (_channel != null) _repo.unsubscribe(_channel!);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await _repo.sendMessage(widget.room.id, text);
      _ctrl.clear();
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
      });
      _markRead();
      _scrollToBottom();
    } catch (e) {
      _toast(_sendErrorMessage(e, '메시지 전송에 실패했어요'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 서버가 한국어 사유를 준 경우(P0001, 예: 나간 방 잠금) 그대로 보여준다.
  String _sendErrorMessage(Object e, String fallback) {
    if (e is PostgrestException && e.code == 'P0001' && e.message.isNotEmpty) {
      return e.message;
    }
    return fallback;
  }

  /// 사진 첨부 — 갤러리에서 선택해 업로드 후 사진 메시지로 전송.
  Future<void> _sendImage() async {
    if (_sending) return;
    final file = await StorageService.instance.pickImage();
    if (file == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final msg = await _repo.sendImageMessage(widget.room.id, file);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
      });
      _markRead();
      _scrollToBottom();
    } catch (e) {
      _toast(_sendErrorMessage(e, '사진 전송에 실패했어요'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 채팅방 나가기 — 확인 후 목록에서 숨기고 방을 닫는다.
  Future<void> _leaveRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text('나가면 채팅 목록에서 사라지고,\n'
            '서로 새 메시지를 보낼 수 없어요.\n'
            '내가 다시 채팅을 시작하면 대화가 이어져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.leaveRoom(widget.room.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (otherId != null)
              ListTile(
                leading:
                    const Icon(Icons.flag_outlined, color: AppColors.danger),
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
              leading:
                  const Icon(Icons.logout_outlined, color: AppColors.danger),
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
    // 헤더 히어로: 사진(블러+스크림, 밝음)=어두운 아이콘 / 무사진(primaryDark)=밝은 아이콘.
    // AnnotatedRegion 이라 화면을 벗어나면 전역 기본(어두움)으로 자동 복원.
    final headerHasPhoto =
        _otherImageUrl != null || widget.room.otherNickname == '고객센터';
    // 타일에서 펼쳐지고/아래로 당기면 타일로 축소되는 공통 래퍼(게시글 상세와 동일 언어).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: headerHasPhoto
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: CollapsibleView(
      originRect: widget.originRect,
      card: widget.cardBuilder,
      scrollController: _scroll,
      // 채팅 목록 타일에서 확장되는 느낌을 강조 — 살짝 튕기며 열리고 시간도 조금 길게.
      expandDuration: const Duration(milliseconds: 520),
      expandCurve: Curves.easeOutBack,
      builder: (context, physics) => Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // 블롭 헤더 히어로 — 게시글 상세와 동일한 디자인 언어(상태바까지 채움,
            // 오버레이 원형 버튼, 확장 완료 시 내려앉는 정착 애니메이션).
            _ChatHeader(
              room: widget.room,
              imageUrl: _otherImageUrl,
              onBack: () => Navigator.maybePop(context),
              onMenu: _openRoomMenu,
            ),
            Expanded(child: _buildMessages(physics)),
            // 상대가 나간 방은 입력을 잠근다(서버도 INSERT 차단).
            if (widget.room.otherLeft)
              const _LockedBar()
            else
              _Composer(
                controller: _ctrl,
                sending: _sending,
                onSend: _send,
                onPickImage: _sendImage,
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMessages(ScrollPhysics physics) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          '첫 메시지를 보내보세요',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
      );
    }
    // reverse:true — 최신 메시지를 맨 아래에 두고 그 위치에서 렌더 시작(진입 시 점프 없음).
    // 데이터는 오래된→최신 순이라, 표시 인덱스는 뒤에서부터 읽는다.
    return ListView.builder(
      controller: _scroll,
      physics: physics, // 드래그 중 잠금은 CollapsibleView 가 제공
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _MessageBubble(
        message: _messages[_messages.length - 1 - i],
        onReport: _reportMessage,
      ),
    );
  }
}

/// 채팅방 상단 히어로 헤더 — 타사용자 프로필 상세와 동일한 문법.
/// 프로필 사진이 있으면 사진 + 하단 점진 블러(경계선 없는 am 스타일),
/// 없으면 primaryDark 배경에 닉네임을 중앙 정렬. 뒤로가기·메뉴는 오버레이
/// 원형 버튼, 확장 완료 시 닉네임이 살짝 내려앉는 정착 모션(CollapseProgress).
class _ChatHeader extends StatefulWidget {
  final ChatRoomSummary room;
  final String? imageUrl;
  final VoidCallback onBack;
  final VoidCallback onMenu;
  const _ChatHeader({
    required this.room,
    required this.imageUrl,
    required this.onBack,
    required this.onMenu,
  });

  @override
  State<_ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<_ChatHeader> {
  // 확장/축소 진행도(0=목록 타일, 1=풀스크린). 닉네임이 이 값을 따라
  // 펼칠 땐 중앙으로 살짝 내려앉고, 축소할 땐 목록 타일의 닉네임 위치로
  // 위로 올라가며 자리를 맞춘다.
  Animation<double>? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progress = CollapseProgress.of(context);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    // 고객센터는 전용 번들 이미지를 프로필처럼 사용.
    final Widget? photoImage = widget.imageUrl != null
        ? Image.network(
            widget.imageUrl!,
            fit: BoxFit.cover,
            cacheWidth: 500, // 블러 배경 — 저해상 디코딩으로 충분
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.primaryDark),
          )
        : (widget.room.otherNickname == '고객센터'
            ? Image.asset('assets/images/cs_profile.png',
                fit: BoxFit.cover, cacheWidth: 500)
            : null);
    final hasPhoto = photoImage != null;
    // 채팅 목록 타일과 동일한 크기 — 좌우 여백 20, 높이 72(상하패딩16+2줄).
    const barH = 72.0;
    final nameColor = hasPhoto ? Colors.white : AppColors.textOnPrimary;
    // 상태바 아래에 떠 있는 둥근(채팅 목록 타일과 동일한 16) 직사각형 바.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad + 8, 20, 6),
      child: SizedBox(
        height: barH,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto)
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 18, // 채팅 목록 타일과 동일한 블러 강도
                    sigmaY: 18,
                    tileMode: ui.TileMode.clamp,
                  ),
                  child: photoImage,
                )
              else
                const ColoredBox(color: AppColors.primaryDark),
              if (hasPhoto)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x33000000)),
                ),
              // 중앙 닉네임 — 진행도에 따라 펼칠 땐 중앙으로 내려앉고,
              // 축소할 땐 목록 타일의 닉네임 위치(위쪽)로 올라가 자연스럽게 인계.
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 56),
                  child: _SettlingName(
                    progress: _progress,
                    text: widget.room.otherNickname,
                    color: nameColor,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 4,
                child: OverlayIconButton(
                  icon: Icons.arrow_back,
                  tooltip: '뒤로',
                  onPressed: widget.onBack,
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 4,
                child: OverlayIconButton(
                  icon: Icons.more_horiz,
                  tooltip: '메뉴',
                  onPressed: widget.onMenu,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 헤더 닉네임 — 확장/축소 진행도에 맞춰 세로 위치를 보간한다.
/// p=1(펼침): 중앙에서 살짝 아래(정착). p→0(축소): 목록 타일의 닉네임 위치(위)로
/// 올라가, 타일로 크로스페이드될 때 위치가 어긋나지 않게 맞춘다.
class _SettlingName extends StatelessWidget {
  final Animation<double>? progress;
  final String text;
  final Color color;
  const _SettlingName({
    required this.progress,
    required this.text,
    required this.color,
  });

  Widget _name() => Text(
        text,
        maxLines: 1,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      );

  Widget _at(double p) {
    // 펼침 +6(정착) ↔ 축소 -10(목록 타일 닉네임 상단 정렬).
    final dy = ui.lerpDouble(-10.0, 6.0, p.clamp(0.0, 1.0))!;
    return Center(
      child: Transform.translate(offset: Offset(0, dy), child: _name()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) return _at(1);
    return AnimatedBuilder(
      animation: p,
      builder: (_, _) => _at(p.value),
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
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block_outlined, size: 15, color: AppColors.textTertiary),
            SizedBox(width: 6),
            Text(
              '상대가 채팅방을 나가 메시지를 보낼 수 없어요',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(
                Icons.add_photo_alternate_outlined,
                color: AppColors.primaryDark,
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
                    fillColor: AppColors.surfaceMuted,
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
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.primaryDark,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textOnPrimary,
                        ),
                      )
                    : const Icon(
                        Icons.arrow_upward,
                        color: AppColors.textOnPrimary,
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
  const _MessageBubble({required this.message, required this.onReport});

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
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            child: GestureDetector(
              onLongPress: mine ? null : () => onReport(message),
              onTap: message.isImage ? () => _openImage(context) : null,
              child: message.isImage ? _imageBody() : _textBody(mine),
            ),
          ),
          if (!mine) ...[
            const SizedBox(width: 6),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 텍스트 버블.
  Widget _textBody(bool mine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? AppColors.primaryDark : AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
        border: Border.all(
          color: mine ? AppColors.primaryDark : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          color: mine ? AppColors.textOnPrimary : AppColors.textPrimary,
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
                  color: AppColors.surfaceMuted,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
          errorBuilder: (_, _, _) => Container(
            width: 200,
            height: 140,
            color: AppColors.surfaceMuted,
            child: const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: AppColors.textTertiary),
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
