import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/community.dart';
import '../services/community_repository.dart';
import '../widgets/role_badge.dart';

/// 게시글 작성 — 카테고리 선택 / 제목·내용 / 약속 일정(선택) / 펫 연결.
/// 카테고리에 따라 입력 UI가 다르게 분기:
///  · walk_together / walk_proxy / care : 펫 다중 선택 + 약속 일정 필수
///  · give_away : 본인 owner 인 펫 1마리만 + 약속 일정 없음
///  · adoption / free : 펫 선택 없음
class PostCreateScreen extends StatefulWidget {
  const PostCreateScreen({super.key});

  @override
  State<PostCreateScreen> createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends State<PostCreateScreen> {
  final _repo = CommunityRepository.instance;

  String _category = 'walk_together';
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  DateTime? _scheduledAt;
  final Set<String> _selectedPetIds = {};

  List<MyPet> _pets = [];
  bool _loadingPets = true;
  bool _submitting = false;

  static const _categories = [
    'walk_together',
    'walk_proxy',
    'care',
    'give_away',
    'adoption',
    'free',
  ];

  bool get _needsSchedule =>
      ['walk_together', 'walk_proxy', 'care'].contains(_category);
  bool get _allowsSchedule => _needsSchedule || _category == 'free';
  bool get _needsPet =>
      ['walk_together', 'walk_proxy', 'care', 'give_away'].contains(_category);
  bool get _giveAway => _category == 'give_away';

  @override
  void initState() {
    super.initState();
    _loadPets();
  }

  Future<void> _loadPets() async {
    try {
      final pets = await _repo.fetchMyPets();
      if (!mounted) return;
      setState(() {
        _pets = pets;
        _loadingPets = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPets = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('새 게시글'),
        actions: [
          TextButton(
            onPressed: (_canSubmit && !_submitting) ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '등록',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('카테고리'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories
                    .map((c) => CategoryChip(
                  category: c,
                  selected: _category == c,
                  onTap: () => setState(() {
                    _category = c;
                    _selectedPetIds.clear();
                    if (!_allowsSchedule) _scheduledAt = null;
                  }),
                ))
                    .toList(),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('제목'),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  hintText: '예) 동탄2동 산책 메이트 구해요',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('내용'),
              TextField(
                controller: _contentCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '자세한 내용을 적어주세요',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_allowsSchedule) ...[
                const SizedBox(height: 20),
                _SectionLabel(_needsSchedule ? '약속 일정' : '약속 일정 (선택)'),
                InkWell(
                  onTap: _pickDateTime,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event,
                            color: AppColors.primaryDark, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _scheduledAt == null
                              ? '일정을 선택하세요'
                              : '${_scheduledAt!.year}년 ${_scheduledAt!.month}월 ${_scheduledAt!.day}일 ${_scheduledAt!.hour}시',
                          style: TextStyle(
                            fontSize: 14,
                            color: _scheduledAt == null
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_needsPet) ...[
                const SizedBox(height: 20),
                _SectionLabel(_giveAway ? '분양할 반려동물 (소유자만, 1마리)' : '연결할 반려동물'),
                if (_loadingPets)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_pets.where((p) => !_giveAway || p.role == 'owner').isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _giveAway
                          ? '분양은 본인이 소유자인 반려동물이 있어야 작성할 수 있어요'
                          : '연결할 반려동물이 없어요. 먼저 반려동물을 등록해주세요',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                    ),
                  ),
                ..._pets.where((p) {
                  if (_giveAway) return p.role == 'owner';
                  return true;
                }).map((p) {
                  final selected = _selectedPetIds.contains(p.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() {
                        if (_giveAway) {
                          _selectedPetIds
                            ..clear()
                            ..add(p.id);
                        } else {
                          if (selected) {
                            _selectedPetIds.remove(p.id);
                          } else {
                            _selectedPetIds.add(p.id);
                          }
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primarySoft.withValues(alpha: 0.3)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : AppColors.border,
                            width: selected ? 1.5 : 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_off,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${p.name}  ·  ${p.species}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            RoleBadge(role: p.role, compact: true),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                if (_giveAway)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '분양이 완료되면 소유권이 자동으로 입양자에게 이전됩니다.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSubmit {
    if (_titleCtrl.text.isEmpty || _contentCtrl.text.isEmpty) return false;
    if (_needsSchedule && _scheduledAt == null) return false;
    if (_needsPet && _selectedPetIds.isEmpty) return false;
    return true;
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await _repo.createPost(
        category: _category,
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        scheduledAt: _allowsSchedule ? _scheduledAt : null,
        petIds: _needsPet ? _selectedPetIds.toList() : const [],
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('게시글을 등록했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// posts 검증 트리거의 한글 메시지를 사용자에게 그대로 노출.
  String _friendlyError(Object e) {
    final s = e.toString();
    final idx = s.indexOf('posts:');
    if (idx >= 0) {
      return s.substring(idx).split('\n').first.replaceFirst('posts:', '').trim();
    }
    return '게시글 등록에 실패했어요';
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}