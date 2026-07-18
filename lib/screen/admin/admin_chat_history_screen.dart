import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../services/admin_repository.dart';
import 'admin_theme.dart';

/// 관리자 — 채팅방 대화 내역(삭제된 메시지 포함) 조회.
/// 신고 상세(채팅 신고)에서 진입해 맥락을 확인하는 용도. 읽기 전용.
class AdminChatHistoryScreen extends StatefulWidget {
  final String roomId;

  /// 신고된 메시지 id(있으면 해당 행을 강조).
  final String? highlightMessageId;

  const AdminChatHistoryScreen({
    super.key,
    required this.roomId,
    this.highlightMessageId,
  });

  @override
  State<AdminChatHistoryScreen> createState() => _AdminChatHistoryScreenState();
}

class _AdminChatHistoryScreenState extends State<AdminChatHistoryScreen> {
  List<AdminChatMessage> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AdminRepository.instance.fetchRoomMessages(
        widget.roomId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '대화 내역을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}.${two(l.month)}.${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '대화 내역'),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '메시지가 없어요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _messageTile(_items[i]),
    );
  }

  Widget _messageTile(AdminChatMessage m) {
    final highlighted = m.id == widget.highlightMessageId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted
            ? context.colors.adminAccentSoft
            : context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted
              ? context.colors.adminAccent
              : context.colors.border,
          width: highlighted ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.senderNickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              if (highlighted) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.adminAccent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '신고 대상',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: context.colors.adminOnAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                _fmt(m.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            m.isImage ? '[사진]' : (m.content ?? ''),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: m.isDeleted
                  ? context.colors.textTertiary
                  : context.colors.textPrimary,
              decoration: m.isDeleted ? TextDecoration.lineThrough : null,
            ),
          ),
          if (m.isImage && m.imageUrl != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                m.imageUrl!,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (m.isDeleted) ...[
            const SizedBox(height: 4),
            Text(
              '삭제됨${m.deletedAt == null ? '' : ' · ${_fmt(m.deletedAt!)}'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
