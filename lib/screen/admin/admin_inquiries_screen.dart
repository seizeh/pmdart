import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/admin.dart';
import '../../motion/motion.dart';
import '../../services/admin/admin_inquiry_repository.dart';
import '../../services/chat_repository.dart';
import '../../theme/app_palette.dart';
import '../../utils/labels.dart' show timeAgo;
import '../chat_room_screen.dart';
import 'admin_theme.dart';

/// 문의 처리 — admin_inquiry 채팅방 목록. 탭하면 방에 참여 후 채팅으로 응대.
class AdminInquiriesScreen extends StatefulWidget {
  const AdminInquiriesScreen({super.key});

  @override
  State<AdminInquiriesScreen> createState() => _AdminInquiriesScreenState();
}

class _AdminInquiriesScreenState extends State<AdminInquiriesScreen> {
  List<AdminInquiry> _items = [];
  bool _loading = true;
  String? _error;
  String? _opening;

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
      final items = await AdminInquiryRepository.instance.listInquiries();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '문의를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _open(AdminInquiry inq) async {
    setState(() => _opening = inq.roomId);
    try {
      await AdminInquiryRepository.instance.joinInquiry(inq.roomId);
      final room = await ChatRepository.instance.fetchRoom(inq.roomId);
      if (!mounted) return;
      if (room == null) {
        _toast('문의방을 열지 못했어요');
        return;
      }
      await Navigator.push(
        context,
        AppPageRoute(builder: (_) => ChatRoomScreen(room: room)),
      );
      if (mounted) unawaited(_load());
    } catch (_) {
      _toast('문의방을 열지 못했어요');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '문의 처리'),
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
          '문의가 없어요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.colors.border),
        itemBuilder: (_, i) {
          final inq = _items[i];
          return InkWell(
            onTap: _opening == null ? () => _open(inq) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: context.colors.primarySoft,
                    child: Text(
                      inq.userNickname.isEmpty
                          ? '?'
                          : inq.userNickname.characters.first,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inq.userNickname,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          inq.lastMessage ?? '메시지 없음',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_opening == inq.roomId)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      inq.lastMessageAt == null
                          ? ''
                          : timeAgo(inq.lastMessageAt!),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
