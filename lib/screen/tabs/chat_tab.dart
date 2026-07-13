import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../motion/motion.dart';
import '../../theme/app_palette.dart';
import '../../data/mock_data.dart' show timeAgo;
import '../../models/chat.dart';
import '../../services/chat_repository.dart';
import '../../services/app_events.dart';
import '../../widgets/gradient_header.dart';
import '../auth/auth_wall_dialog.dart';
import '../chat_room_screen.dart';

/// 채팅 탭 — 진행 중인 대화 목록(실데이터).
class ChatTab extends StatefulWidget {
  final bool isGuest;
  const ChatTab({super.key, this.isGuest = false});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _repo = ChatRepository.instance;
  List<ChatRoomSummary> _rooms = [];
  bool _loading = true;
  String? _error;

  // 채팅 타일별 GlobalKey — 탭 시 타일 위치를 캡처해 그 자리에서 펼치고 축소하는 데 사용.
  final _roomKeys = <String, GlobalKey>{};

  // 상세로 열려있는 방 id — 그 타일은 열린 동안 투명(빈자리)으로 두어 축소가 겹침 없이 안착.
  String? _openedRoomId;

  // 타일의 현재 화면상 사각형(축소 도착 지점). 못 찾으면 null.
  Rect? _roomRect(String id) {
    final box = _roomKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openRoom(ChatRoomSummary room) async {
    final rect = _roomRect(room.id);
    if (rect != null) setState(() => _openedRoomId = room.id); // 빈자리로
    await Navigator.push(
      context,
      rect == null
          ? AppPageRoute(builder: (_) => ChatRoomScreen(room: room))
          : CollapseRoute(
              builder: (_) => ChatRoomScreen(
                room: room,
                originRect: rect,
              ),
            ),
    );
    if (!mounted) return;
    setState(() => _openedRoomId = null); // 타일 복원
    _load(silent: true); // 읽음/새 메시지 반영
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _load();
      AppEvents.instance.chat.addListener(_onChatChanged);
    }
  }

  @override
  void dispose() {
    AppEvents.instance.chat.removeListener(_onChatChanged);
    super.dispose();
  }

  void _onChatChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rooms = await _repo.fetchRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_rooms.isEmpty) _error = '채팅을 불러오지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) return const _GuestChat();

    final topInset = MediaQuery.of(context).padding.top;
    // 메인(커뮤니티)과 동일하게: 리스트가 상단 그라데이션 헤더 아래로 스크롤되며 페이드.
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(topInset + 56)),
          GradientHeader(
            topInset: topInset,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                '채팅',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primaryDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double topPad) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(message: _error!, onRetry: _load);
    }
    if (_rooms.isEmpty) {
      return const _MessageState(
        message: '아직 진행 중인 대화가 없어요.\n게시글에서 상대에게 채팅을 시작해보세요!',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: topPad,
      child: ListView.separated(
        padding: EdgeInsets.only(left: 20, right: 20, top: topPad + 14),
        itemCount: _rooms.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final room = _rooms[i];
          final key = _roomKeys.putIfAbsent(room.id, () => GlobalKey());
          return KeyedSubtree(
            key: key,
            child: Opacity(
              opacity: room.id == _openedRoomId ? 0.0 : 1.0,
              child: RepaintBoundary(
                child: _ChatRoomTile(room: room, onTap: () => _openRoom(room)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final ChatRoomSummary room;
  final VoidCallback onTap;
  const _ChatRoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final photo = room.otherProfileImageUrl;
    // 고객센터는 전용 번들 이미지를 프로필처럼 사용.
    final Widget? bgImage = photo != null
        ? Image.network(
            photo,
            fit: BoxFit.cover,
            cacheWidth: 400, // 블러 배경 — 저해상 디코딩으로 충분(비용·메모리 절감)
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        : (room.isSupport
            ? Image.asset('assets/images/cs_profile.png',
                fit: BoxFit.cover, cacheWidth: 400)
            : null);
    // 사진 없는 상대는 채팅방 헤더와 동일한 primaryDark 프로필로 —
    // 흰 타일 → 진갈색 헤더로 바뀌던 이질감 제거.
    final hasPhoto = bgImage != null;
    return Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hasPhoto ? null : context.colors.primaryDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            // 상대 프로필 사진을 타일 전체 블러 배경으로(채팅방 헤더와 동일 문법).
            if (bgImage != null)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 18,
                    sigmaY: 18,
                    tileMode: ui.TileMode.clamp,
                  ),
                  child: bgImage,
                ),
              ),
            // 가독용 스크림 — 모드별 베일(라이트: 흰, 다크: 웜 다크)로 텍스트 대비 확보.
            if (bgImage != null)
              Positioned.fill(
                child: ColoredBox(
                  color: context.isDark
                      ? const Color(0xB3161616)
                      : const Color(0xB3FFFFFF),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Stack(
                children: [
            // 본문 — 채팅방 상세 헤더(중앙 닉네임)와 축소 전환 형태가 이어지도록
            // 아바타 없이 가운데 정렬로만 구성한다.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 72),
                  child: Text(
                    room.otherNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: hasPhoto
                          ? context.colors.textPrimary
                          : context.colors.textOnPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    room.lastMessage.isEmpty ? '대화를 시작해보세요' : room.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: hasPhoto
                          ? context.colors.textSecondary
                          : context.colors.textOnPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            // 마지막 대화 시각 — 우측 상단.
            if (room.lastMessageAt != null)
              Positioned(
                top: 0,
                right: 0,
                child: Text(
                  timeAgo(room.lastMessageAt!),
                  style: TextStyle(
                    fontSize: 11,
                    color: hasPhoto
                        ? context.colors.textTertiary
                        : context.colors.textOnPrimary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            // 안읽음 뱃지 — 우측 하단.
            if (room.unreadCount > 0)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.colors.danger,
                    borderRadius: const BorderRadius.all(Radius.circular(100)),
                  ),
                  child: Text(
                    '${room.unreadCount}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _MessageState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: context.colors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuestChat extends StatelessWidget {
  const _GuestChat();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: context.colors.primarySoft,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: context.colors.primaryDark,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '채팅은 로그인 후 이용할 수 있어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => AuthWallDialog.show(
                    context,
                    message: '채팅은 로그인 후 이용할 수 있어요',
                  ),
                  child: const Text('로그인하러 가기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
