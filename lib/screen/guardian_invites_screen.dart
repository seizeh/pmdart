import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show timeAgo;
import '../services/pet_repository.dart';

/// 받은 공동보호자 초대 — 수락/거절.
/// 수락 시 트리거가 보호자로 등록. 단, 진행 중 약속의 지원자면 차단되어 안내한다.
class GuardianInvitesScreen extends StatefulWidget {
  const GuardianInvitesScreen({super.key});

  @override
  State<GuardianInvitesScreen> createState() => _GuardianInvitesScreenState();
}

class _GuardianInvitesScreenState extends State<GuardianInvitesScreen> {
  final _repo = PetRepository.instance;
  List<GuardianInvite> _items = [];
  bool _loading = true;
  String? _error;
  String? _busy; // 처리 중인 초대 id

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
      final items = await _repo.fetchPendingInvites();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했어요';
        _loading = false;
      });
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _accept(GuardianInvite inv) async {
    setState(() => _busy = inv.id);
    try {
      await _repo.acceptInvite(inv.id);
      if (!mounted) return;
      _toast('${inv.petName}의 공동보호자가 되었어요');
      setState(() => _items = _items.where((e) => e.id != inv.id).toList());
    } on PostgrestException catch (e) {
      // DB 트리거의 차단 메시지(진행 중 약속 등)를 그대로 안내
      _toast(e.message);
    } catch (_) {
      _toast('수락하지 못했어요. 잠시 후 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _decline(GuardianInvite inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('초대를 거절할까요?'),
        content: Text('${inv.inviterNickname}님의 ${inv.petName} 공동보호자 초대를 거절합니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('거절', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = inv.id);
    try {
      await _repo.declineInvite(inv.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != inv.id).toList());
    } catch (_) {
      _toast('거절하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('받은 보호자 초대')),
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
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('받은 초대가 없어요',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _InviteCard(
          invite: _items[i],
          busy: _busy == _items[i].id,
          onAccept: () => _accept(_items[i]),
          onDecline: () => _decline(_items[i]),
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final GuardianInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                  image: invite.petImageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(invite.petImageUrl!),
                          fit: BoxFit.cover)
                      : null,
                ),
                child: invite.petImageUrl == null
                    ? const Icon(Icons.pets,
                        color: AppColors.primaryDark, size: 22)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.petName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${invite.inviterNickname}님이 공동보호자로 초대했어요',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                timeAgo(invite.createdAt),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size(0, 42),
                  ),
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    minimumSize: const Size(0, 42),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('수락'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
