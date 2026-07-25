import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../data/mock_data.dart' show categoryLabel;
import '../models/community.dart';
import '../models/profile.dart';
import '../motion/motion.dart';
import '../services/business_repository.dart';
import '../services/community_repository.dart';
import '../services/location_service.dart';
import '../services/photo_verify_repository.dart';
import '../services/profile_repository.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import '../widgets/blob_background.dart';
import '../widgets/media_widgets.dart' show VideoPlayBadge;
import '../widgets/role_badge.dart';
import 'image_crop_screen.dart';

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

  // 계정 모드 — 업체(business) 글은 카테고리 선택 없이 항상 '소식'(news)으로
  // 등록된다(서버 트리거도 동일하게 강제). null = 확인 중(등록 버튼 잠금).
  String? _activeMode;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  DateTime? _scheduledAt;
  final Set<String> _selectedPetIds = {};

  List<MyPet> _pets = [];
  bool _loadingPets = true;
  bool _submitting = false;

  UploadedImage? _uploadedImage;
  // 첨부 동영상(자유·소식만, 서버 CHECK 동일) — 사진과 상호 배타(단일 미디어 슬롯).
  UploadedVideo? _uploadedVideo;
  bool _uploadingImage = false;
  // 사진 필수 카테고리(walk/care/give_away)에서 서버 검증 통과 시 받는 1회용 토큰.
  String? _photoToken;
  // 검증 사진이 묶인(촬영한) 펫 id — 이 펫이 선택 해제되면 사진을 무효화한다.
  String? _photoPetId;

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

  // 자유(free)·입양(adoption)·소식(news)을 제외한 카테고리는 사진 촬영 인증 대상.
  bool get _isPhotoCategory =>
      !['free', 'adoption', 'news'].contains(_category);

  // 영상 첨부 가능 카테고리 — 서버 CHECK 와 동일(free·news 만).
  bool get _allowsVideo => _category == 'free' || _category == 'news';

  // 현재 선택(연결)한 반려동물들.
  List<MyPet> get _selectedPets =>
      _pets.where((p) => _selectedPetIds.contains(p.id)).toList();

  // 촬영 인증이 필요한지 — 신뢰도는 펫별. 선택한 펫 중 미인증(trust<3)이 있을 때만 필요.
  // 선택한 펫이 모두 신뢰도 3 이상이면 사진 인증 생략(사진은 선택적 첨부만).
  bool get _needsPhoto =>
      _isPhotoCategory && _selectedPets.any((p) => !p.isTrusted);

  // 현재 위치가 인증 동네와 다를 때 경고 — 게시글은 인증 동네 기준으로 등록됨.
  String? _currentDong; // 지금 있는 동
  String? _verifiedDong; // 인증한 동
  bool get _regionMismatch =>
      _currentDong != null &&
      _verifiedDong != null &&
      _currentDong != _verifiedDong;

  /// 카테고리 변경 — 카테고리에 따라 입력 경로가 달라지므로 관련 상태 초기화.
  void _selectCategory(String c) {
    setState(() {
      _category = c;
      _selectedPetIds.clear();
      if (!_allowsSchedule) _scheduledAt = null;
      // 카테고리가 바뀌면 사진 입력 경로(카메라/갤러리)가 달라지므로 초기화.
      _uploadedImage = null;
      _uploadedVideo = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = false;
    });
  }

  // 카테고리 태그 인라인 확장 상태 — 탭하면 태그 자리가 전체 카테고리 알약으로
  // 펼쳐지고, 하나를 고르면 다시 접힌다(바텀시트 없음).
  bool _categoryExpanded = false;

  // ── 편집형 미리보기 카드 — 피드 카드(PostCard)와 동일한 시각 문법에
  //    제목 인라인 입력·카테고리/일정 탭 편집·좌상단 사진 버튼을 얹은 것.
  //    (레이아웃을 바꿀 땐 widgets/post_card.dart 와 함께 맞출 것)

  Widget _editableCard() {
    final color = categoryColor(context, _category);
    // 영상 첨부 시 포스터를 대표 이미지로(포스터 없으면 어두운 타일 + ▶).
    final videoAttached = _uploadedVideo != null;
    final photoUrl = videoAttached
        ? _uploadedVideo!.thumbUrl
        : _uploadedImage?.url;
    final hasPhoto = photoUrl != null || videoAttached;
    final biz = _activeMode == 'business';
    final me = SessionManager.instance.user;
    final content = _contentCtrl.text.trim();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: AspectRatio(
        aspectRatio: kPostImageAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 배경 — 대표사진(영상은 포스터) 또는 카테고리 색 블롭(피드와 동일).
            if (photoUrl != null)
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                cacheWidth: 1200,
                errorBuilder: (_, _, _) => videoAttached
                    ? const ColoredBox(color: Color(0xFF2B2B2B))
                    : BlobBackground(seed: 'preview/$_category', color: color),
              )
            else if (videoAttached)
              const ColoredBox(color: Color(0xFF2B2B2B))
            else
              BlobBackground(seed: 'preview/$_category', color: color),
            // 점진 블러 — 피드 카드와 동일한 하단 뭉갬.
            if (photoUrl != null)
              Positioned.fill(
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0x00FFFFFF),
                      Color(0xFFFFFFFF),
                    ],
                    stops: [0.0, 0.42, 0.85],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 22,
                      sigmaY: 22,
                      tileMode: ui.TileMode.clamp,
                    ),
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            // 사진 없는 글 — 본문 히어로(아래 '내용'에서 입력한 값이 실시간 반영).
            if (!hasPhoto)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 170),
                  child: Center(
                    child: Text(
                      content.isEmpty ? '내용이 여기에 표시돼요' : content,
                      textAlign: TextAlign.center,
                      maxLines: 9,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: content.isEmpty
                            ? context.colors.textTertiary
                            : context.colors.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            // 영상 첨부 — 중앙 ▶ 배지(피드 카드와 동일 문법).
            if (videoAttached) const Center(child: VideoPlayBadge(size: 52)),
            // 가독용 스크림(피드와 동일).
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 210,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x73000000)],
                  ),
                ),
              ),
            ),
            // 좌상단 — 사진 추가/교체(+제거) 버튼.
            Positioned(
              top: 10,
              left: 10,
              child: Row(
                children: [
                  _cardIconButton(
                    icon: hasPhoto
                        ? Icons.photo_camera_outlined
                        : Icons.add_a_photo_outlined,
                    tooltip: _needsPhoto
                        ? '사진 촬영(인증)'
                        : (_allowsVideo ? '사진·동영상 추가' : '사진 추가'),
                    busy: _uploadingImage,
                    onTap: _onPhotoTap,
                  ),
                  if (hasPhoto && !_uploadingImage) ...[
                    const SizedBox(width: 8),
                    _cardIconButton(
                      icon: Icons.close,
                      tooltip: '사진 제거',
                      onTap: _removeImage,
                    ),
                  ],
                ],
              ),
            ),
            // 하단 정보 — 카테고리·일정은 탭 편집, 제목은 그 자리에서 입력.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 카테고리 — 탭하면 태그가 제자리에서 전체 목록으로 펼쳐지고,
                    // 하나를 고르면(같은 걸 고르면 그대로) 다시 접힌다.
                    // 모션은 앱 공통 스프링 언어: 확장은 standard 스프링,
                    // 알약들은 Entrance 스태거로 튀어오르고, 탭엔 Pressable 촉감.
                    AnimatedSize(
                      duration: MotionDurations.base,
                      curve: SpringCurve.standard,
                      alignment: Alignment.bottomLeft,
                      child: _categoryExpanded && !biz
                          ? Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final (i, c) in _categories.indexed)
                                  Entrance(
                                    index: i,
                                    offsetY: 12,
                                    fromScale: 0.85,
                                    child: Pressable(
                                      scaleTo: 0.9,
                                      borderRadius: BorderRadius.circular(100),
                                      onTap: () {
                                        if (c != _category) _selectCategory(c);
                                        setState(
                                          () => _categoryExpanded = false,
                                        );
                                      },
                                      child: _previewPill(
                                        text: categoryLabel(c),
                                        textColor: categoryColor(context, c),
                                        selected: c == _category,
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : Row(
                              children: [
                                // 선택 직후엔 태그가 살짝 튀며 안착 — 선택 피드백.
                                KeyedSubtree(
                                  key: ValueKey('cat-tag-$_category'),
                                  child: Entrance(
                                    index: 0,
                                    offsetY: 6,
                                    fromScale: 0.8,
                                    child: Pressable(
                                      scaleTo: 0.9,
                                      borderRadius: BorderRadius.circular(100),
                                      onTap: biz
                                          ? null
                                          : () => setState(
                                              () => _categoryExpanded = true,
                                            ),
                                      child: _previewPill(
                                        text: categoryLabel(_category),
                                        textColor: color,
                                        trailing: biz
                                            ? null
                                            : Icons.expand_more,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!biz && _verifiedDong != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.place_outlined,
                                          size: 13,
                                          color: Color(0xCCFFFFFF),
                                        ),
                                        const SizedBox(width: 2),
                                        Flexible(
                                          child: Text(
                                            _verifiedDong!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xE6FFFFFF),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                const Text(
                                  '방금 전',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xCCFFFFFF),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 10),
                    // 제목 — 카드 위에서 바로 입력(피드 타이포와 동일).
                    TextField(
                      controller: _titleCtrl,
                      maxLines: 1,
                      onChanged: (_) => setState(() {}),
                      cursorColor: Colors.white,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintText: '제목을 입력하세요',
                        hintStyle: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0x99FFFFFF),
                        ),
                      ),
                    ),
                    if (hasPhoto) ...[
                      const SizedBox(height: 4),
                      Text(
                        content.isEmpty ? '내용은 아래에서 입력해요' : content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: content.isEmpty
                              ? const Color(0x99FFFFFF)
                              : const Color(0xE0FFFFFF),
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (_allowsSchedule) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _pickDateTime,
                        child: _previewMetaPill(
                          icon: Icons.event_outlined,
                          label: _scheduledAt == null
                              ? (_needsSchedule ? '약속 일정 선택 (필수)' : '약속 일정 선택')
                              : '${_scheduledAt!.month}/${_scheduledAt!.day} ${_scheduledAt!.hour}시',
                          editable: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          biz
                              ? (_bizName ?? me?.nickname ?? '')
                              : (me?.nickname ?? ''),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xE6FFFFFF),
                          ),
                        ),
                        const Spacer(),
                        _previewStat(Icons.favorite_border),
                        const SizedBox(width: 14),
                        _previewStat(Icons.chat_bubble_outline),
                        const SizedBox(width: 14),
                        _previewStat(Icons.visibility_outlined),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 카드 위 원형 아이콘 버튼(좌상단 사진 컨트롤) — 사진 위 가독용 프로스트.
  Widget _cardIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0x66000000),
            shape: BoxShape.circle,
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }

  /// 카테고리 태그(흰 필름 알약) — 피드 카드와 동일 + 편집 힌트(▾).
  /// [selected] 는 인라인 확장 목록에서 현재 카테고리 강조(색 채움 + 흰 글자).
  Widget _previewPill({
    required String text,
    required Color textColor,
    IconData? trailing,
    bool selected = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? textColor : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : textColor,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: 13, color: textColor),
          ],
        ],
      ),
    );
  }

  /// 일정 알약 — 피드 카드의 메타 알약과 동일 + 편집 힌트(▾).
  Widget _previewMetaPill({
    required IconData icon,
    required String label,
    bool editable = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 13,
              color: context.colors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewStat(IconData icon) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: const Color(0xCCFFFFFF)),
      const SizedBox(width: 4),
      const Text(
        '0',
        style: TextStyle(
          fontSize: 12,
          color: Color(0xCCFFFFFF),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    _loadMode();
    _loadPets();
    _checkRegion();
  }

  // 미리보기 작성자 표시 — 업체 모드면 상호(로드 전엔 빈 값 → 닉네임 폴백).
  String? _bizName;

  Future<void> _loadMode() async {
    final mode = await BusinessRepository.instance.fetchActiveMode();
    if (!mounted) return;
    if (mode == 'business') {
      // 미리보기에 상호를 보여주기 위해 업체 프로필도 로드(실패해도 무해).
      unawaited(
        BusinessRepository.instance
            .fetchMine()
            .then((biz) {
              if (mounted && biz != null) {
                setState(() => _bizName = biz.businessName);
              }
            })
            .catchError((_) {}),
      );
    }
    setState(() {
      _activeMode = mode;
      if (mode == 'business') _category = 'news';
    });
  }

  /// 현재 위치 동 vs 인증 동 비교(베스트에포트). 위치 없으면 경고 안 함.
  Future<void> _checkRegion() async {
    try {
      final reg = await ProfileRepository.instance.fetchRegion();
      final verified = ProfileData.regionNameFromAddress(
        reg.address,
        verified: reg.verified,
      );
      if (verified == null) return; // 미인증이면 비교 의미 없음
      // 인증 동은 미리보기(위치 표시)에도 쓰므로 위치 조회 성패와 무관하게 먼저 반영.
      if (mounted) setState(() => _verifiedDong = verified);
      final loc = await LocationService.instance.getCurrentPosition();
      if (loc.status != LocationStatus.ok || loc.position == null) return;
      final cur = await ProfileRepository.instance.regionNameAt(
        loc.position!.latitude,
        loc.position!.longitude,
      );
      if (!mounted || cur == null) return;
      setState(() {
        _verifiedDong = verified;
        _currentDong = cur;
      });
    } catch (_) {
      /* 베스트에포트 — 실패 시 경고 없음 */
    }
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

  /// 사진 영역 탭 분기.
  ///  · 자유/입양: 갤러리 자유 업로드.
  ///  · 사진 인증 카테고리: 반려동물을 먼저 선택해야 함(선택 전엔 갤러리 못 엶).
  ///    - 선택 펫 중 미인증(trust<3) 포함 → 직접 촬영(서버 검증)만.
  ///    - 선택 펫이 모두 인증(신뢰) → 직접 촬영(서버 검증) / 갤러리 불러오기 선택.
  Future<void> _onPhotoTap() async {
    if (!_isPhotoCategory) {
      // 자유·소식은 영상도 허용(서버 CHECK 동일) — 사진/동영상 선택 시트.
      if (_allowsVideo) return _chooseMediaType();
      return _pickAndUpload(fromCamera: false);
    }
    if (_selectedPets.isEmpty) {
      _toast('먼저 인증할 반려동물을 선택해주세요');
      return;
    }
    if (_selectedPets.any((p) => !p.isTrusted)) {
      return _captureAndVerify(); // 미인증 펫 포함 → 촬영 인증 필수
    }
    return _choosePhotoSource(); // 모두 인증된 펫 → 촬영/갤러리 선택
  }

  /// 인증된(신뢰) 펫만 선택된 경우 — 촬영/갤러리 소스 선택 시트.
  Future<void> _choosePhotoSource() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '사진 추가',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: context.colors.primaryDark,
              ),
              title: const Text('직접 촬영'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: context.colors.primaryDark,
              ),
              title: const Text('갤러리에서 불러오기'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (src == 'camera') return _captureAndVerify();
    if (src == 'gallery') return _pickAndUpload(fromCamera: false);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// 자유·소식 첨부 — 사진/동영상 선택 시트.
  Future<void> _chooseMediaType() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '첨부하기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: context.colors.primaryDark,
              ),
              title: const Text('사진'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: Icon(
                Icons.videocam_outlined,
                color: context.colors.primaryDark,
              ),
              title: const Text('동영상'),
              subtitle: const Text('최대 60초 · 100MB'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (src == 'photo') return _pickAndUpload(fromCamera: false);
    if (src == 'video') return _pickAndUploadVideo();
  }

  /// 동영상 선택 → 업로드(포스터 생성 포함). 100MB 초과는 업로드 전에 안내.
  Future<void> _pickAndUploadVideo() async {
    final XFile? file;
    try {
      file = await StorageService.instance.pickVideo();
    } catch (_) {
      _toast('동영상을 불러오지 못했어요');
      return;
    }
    if (file == null) return;
    setState(() {
      _uploadedImage = null;
      _uploadedVideo = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = true;
    });
    try {
      final up = await StorageService.instance.uploadVideo(
        file,
        category: 'posts',
      );
      if (!mounted) return;
      setState(() {
        _uploadedVideo = up;
        _uploadingImage = false;
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _toast(e.message); // 100MB 초과 등 한국어 안내
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      _toast('동영상 업로드에 실패했어요');
    }
  }

  /// 사진 필수 카테고리(walk/care/give_away): 촬영 대상 펫 결정 → 카메라 촬영 →
  /// 위치·AI 실존 + 등록 펫 개체 대조. 통과 시 서버 URL/토큰 보관.
  Future<void> _captureAndVerify() async {
    // 1) 촬영 대상 펫 결정 — 연결한 펫 중 아무나(인증 여부 무관, 한 마리 통과로 충분).
    //    여러 마리를 연결했으면 사진 속 펫이 누구인지 먼저 묻는다.
    final candidates = _selectedPets;
    if (candidates.isEmpty) {
      _toast('먼저 반려동물을 선택해주세요');
      return;
    }
    final target = candidates.length == 1
        ? candidates.first
        : await _choosePhotoPet(candidates);
    if (target == null) return; // 선택 취소

    // 2) 신원 인증(영상)이 안 된 펫이면 안내(인증은 펫 등록/수정 화면에서 진행)
    if (!target.isIdentityVerified) {
      _toast('${target.name}의 신원 인증(영상)을 먼저 완료해주세요');
      return;
    }

    // 3) 촬영 → 검증(등록 펫과 동일개체 매칭)
    // 카메라 실패(권한 거부·기기 미지원 등)는 예외로 오므로 잡아서 알린다 —
    // 안 잡으면 버튼이 무반응인 것처럼 보인다.
    final XFile? shot;
    try {
      shot = await StorageService.instance.capturePostPhoto();
    } catch (e) {
      _toast('카메라를 열지 못했어요: $e');
      return;
    }
    if (shot == null) return;
    setState(() {
      _uploadedImage = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = true;
    });
    final res = await PhotoVerifyRepository.instance.verifyPostPhoto(
      shot,
      petId: target.id,
    );
    if (!mounted) return;
    if (res.pass && res.imageUrl != null && res.token != null) {
      setState(() {
        _uploadedImage = UploadedImage(
          url: res.imageUrl!,
          mime: shot!.mimeType ?? 'image/jpeg',
          size: 0,
        );
        _photoToken = res.token;
        _photoPetId = target.id;
        _uploadingImage = false;
      });
    } else {
      setState(() => _uploadingImage = false);
      _toast(res.message);
    }
  }

  /// 여러 마리를 연결한 경우, 사진 속 반려동물을 고른다.
  Future<MyPet?> _choosePhotoPet(List<MyPet> candidates) {
    return showModalBottomSheet<MyPet>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '사진 속 반려동물을 선택하세요',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            ...candidates.map(
              (p) => ListTile(
                title: Text('${p.name}  ·  ${p.species}'),
                subtitle: p.isIdentityVerified
                    ? null
                    : Text(
                        '신원 인증 필요',
                        style: TextStyle(
                          color: context.colors.warning,
                          fontSize: 12,
                        ),
                      ),
                onTap: () => Navigator.pop(ctx, p),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 검증 없는 사진 첨부(자유/입양, 또는 인증된 펫의 선택 촬영/갤러리).
  /// [fromCamera] 면 카메라 촬영, 아니면 갤러리 선택 → 표시 비율 크롭 → 업로드.
  Future<void> _pickAndUpload({required bool fromCamera}) async {
    final file = fromCamera
        ? await StorageService.instance.capturePostPhoto()
        : await StorageService.instance.pickImage();
    if (file == null) return;
    final raw = await file.readAsBytes();
    if (!mounted) return;
    // 보여질 영역 조정 화면(취소하면 첨부 중단).
    final cropped = await Navigator.push<Uint8List>(
      context,
      AppPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(bytes: raw),
      ),
    );
    if (cropped == null) return;
    setState(() {
      _uploadedImage = null;
      _uploadedVideo = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = true;
    });
    try {
      final up = await StorageService.instance.uploadBytes(
        cropped,
        category: 'posts',
        ext: 'jpg',
        mime: 'image/jpeg',
      );
      if (!mounted) return;
      setState(() {
        _uploadedImage = up;
        _uploadingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploadingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('사진 업로드에 실패했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _uploadedImage = null;
      _uploadedVideo = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = false;
    });
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
      backgroundColor: context.colors.background,
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
              // 지역 불일치 경고는 개인 글만 — 업체 소식은 사업장 주소 기준.
              if (_regionMismatch && _activeMode == 'personal') ...[
                _RegionWarning(
                  current: _currentDong!,
                  verified: _verifiedDong!,
                ),
                const SizedBox(height: 16),
              ],
              // 미리보기 = 편집 캔버스. 카드 위에서 직접 수정한다:
              //  · 제목: 카드의 제목 자리를 탭해 바로 입력
              //  · 카테고리: 카테고리 태그 탭 → 선택 시트(개인 모드만)
              //  · 약속 일정: 일정 알약 탭 → 날짜/시간 선택
              //  · 사진: 좌상단 카메라 아이콘(사진 있으면 X 로 제거)
              // 내용·반려동물 선택만 아래 별도 섹션에서.
              const _SectionLabel('미리보기'),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '커뮤니티에 이렇게 보여요 — 카드를 직접 탭해서 수정하세요',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              _editableCard(),
              if (_needsPhoto)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '📷 사진 인증 카테고리예요 — 아래에서 반려동물을 선택한 뒤, '
                    '카드 좌상단 카메라로 그 아이를 직접 촬영해주세요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              const _SectionLabel('내용'),
              TextField(
                controller: _contentCtrl,
                maxLines: 8,
                decoration: const InputDecoration(hintText: '자세한 내용을 적어주세요'),
                onChanged: (_) => setState(() {}),
              ),
              if (_needsPet) ...[
                const SizedBox(height: 20),
                _SectionLabel(_giveAway ? '분양할 반려동물 (소유자만, 1마리)' : '연결할 반려동물'),
                if (_loadingPets)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_pets
                    .where((p) => !_giveAway || p.role == 'owner')
                    .isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _giveAway
                          ? '분양은 본인이 소유자인 반려동물이 있어야 작성할 수 있어요'
                          : '연결할 반려동물이 없어요. 먼저 반려동물을 등록해주세요',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ..._pets
                    .where((p) {
                      if (_giveAway) return p.role == 'owner';
                      return true;
                    })
                    .map((p) {
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
                            // 검증 사진이 묶인 펫이 선택 해제되면 사진을 무효화한다.
                            if (_photoPetId != null &&
                                !_selectedPetIds.contains(_photoPetId)) {
                              _uploadedImage = null;
                              _photoToken = null;
                              _photoPetId = null;
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? context.colors.primarySoft.withValues(
                                      alpha: 0.3,
                                    )
                                  : context.colors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? context.colors.primary
                                    : context.colors.border,
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
                                      ? context.colors.primary
                                      : context.colors.textTertiary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${p.name}  ·  ${p.species}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.colors.textPrimary,
                                    ),
                                  ),
                                ),
                                // 신뢰도 3 이상 — 사진 인증 없이 게시 가능.
                                if (p.isTrusted && _isPhotoCategory) ...[
                                  const _TrustBadge(),
                                  const SizedBox(width: 6),
                                ],
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
                      color: context.colors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: context.colors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '분양이 완료되면 소유권이 자동으로 입양자에게 이전됩니다.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textPrimary,
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
    if (_activeMode == null) return false; // 모드 확인 전 — 잘못된 카테고리 방지
    if (_uploadingImage) return false;
    if (_titleCtrl.text.isEmpty || _contentCtrl.text.isEmpty) return false;
    if (_needsPhoto && (_uploadedImage == null || _photoToken == null)) {
      return false;
    }
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
      // 원형 다이얼 대신 숫자 입력식 — 시간은 키패드로 바로 입력한다.
      initialEntryMode: TimePickerEntryMode.inputOnly,
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
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
        // 단일 미디어 슬롯 — 영상이면 image_url 에 영상, thumb 에 포스터.
        imageUrl: _uploadedVideo?.url ?? _uploadedImage?.url,
        imageMime: _uploadedVideo?.mime ?? _uploadedImage?.mime,
        imageSize: _uploadedVideo?.size ?? _uploadedImage?.size,
        imageThumbUrl: _uploadedVideo?.thumbUrl,
        photoToken: _photoToken,
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
      return s
          .substring(idx)
          .split('\n')
          .first
          .replaceFirst('posts:', '')
          .trim();
    }
    return '게시글 등록에 실패했어요';
  }
}

/// 현재 위치가 인증 동네와 다를 때 경고 배너.
class _RegionWarning extends StatelessWidget {
  final String current;
  final String verified;
  const _RegionWarning({required this.current, required this.verified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.colors.warning.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: context.colors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '지금 계신 곳($current)이 인증 동네($verified)와 달라요.\n'
              '이 게시글은 인증 동네($verified) 기준으로 등록됩니다.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 신뢰 펫 배지 — 약속·평가로 신뢰도 3 이상 달성 → 사진 인증 면제 표시.
class _TrustBadge extends StatelessWidget {
  const _TrustBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: 13,
            color: context.colors.primaryDark,
          ),
          SizedBox(width: 3),
          Text(
            '인증 면제',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.primaryDark,
            ),
          ),
        ],
      ),
    );
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
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}
