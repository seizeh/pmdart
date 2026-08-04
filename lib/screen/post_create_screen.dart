import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:image_picker/image_picker.dart' show XFile;

import '../data/mock_data.dart' show categoryLabel;
import '../models/community.dart';
import '../models/profile.dart';
import '../motion/motion.dart';
import '../services/business/mode_repository.dart';
import '../services/business/profile_repository.dart';
import '../services/community_repository.dart';
import '../services/location_service.dart';
import '../services/photo_verify_repository.dart';
import '../services/profile_repository.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import '../widgets/blob_background.dart';
import '../widgets/media_widgets.dart' show VideoPlayBadge;
import '../widgets/post_editor_parts.dart';
import '../widgets/post_media_hero.dart' show MediaOverlayPanel;
import '../widgets/role_badge.dart';
import 'image_crop_screen.dart';

/// 게시글 작성 — 카테고리 선택 / 제목·내용 / 약속 일정(선택) / 펫 연결.
/// 카테고리에 따라 입력 UI가 다르게 분기:
///  · walk_together / walk_proxy / care : 펫 다중 선택 + 약속 일정 필수
///  · give_away : 본인 owner 인 펫 1마리만 + 약속 일정 없음
///  · adoption / free : 펫 선택 없음
///
/// 화면 = 게시글 상세(쇼츠형)와 같은 **전체화면 카드 하나**다. 앱바 제목·뒤로가기
/// 없이 미디어(사진/영상 포스터/블롭)가 화면을 채우고, 하단 오버레이에서 모든
/// 입력을 한다(카테고리·제목·본문·일정·펫). 닫기는 상세와 동일하게 **아래로
/// 쓸어내리기**(또는 시스템 뒤로가기) — [originRect] 로 준 원본(글쓰기 버튼)으로
/// 축소되며 닫힌다.
class PostCreateScreen extends StatefulWidget {
  /// 펼쳐지고·축소될 원본 사각형(글쓰기 FAB). null 이면 축소 제스처 없이 일반 화면.
  final Rect? originRect;

  /// 축소 안착 시 크로스페이드할 원본 위젯(FAB 고스트).
  final WidgetBuilder? cardBuilder;

  /// 원본의 모서리 곡률 — 축소가 안착할 때 곡률이 튀지 않도록 원본과 맞춘다.
  final double cardRadius;

  const PostCreateScreen({
    super.key,
    this.originRect,
    this.cardBuilder,
    this.cardRadius = 28,
  });

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

  // 아래로 당기면 원본(글쓰기 버튼)으로 축소되는 CollapsibleView 용 스크롤 컨트롤러.
  final _scroll = ScrollController();

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

  // 촬영 인증이 필요한지 — 게이트는 펫별 게시글 순번(1·4·10번째)이다.
  // 선택한 펫 중 하나라도 그 순번이면 필요하고, 아니면 생략(사진은 선택 첨부).
  // 서버(create_post_verified → app.needs_photo_gate)와 같은 규칙.
  bool get _needsPhoto =>
      _isPhotoCategory && _selectedPets.any((p) => p.needsPhotoGate);

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

  // ── 편집형 전체화면 에디터 — 게시글 상세(PostMediaHero)와 동일한 시각 문법:
  //    미디어(사진/영상 포스터/블롭)가 화면을 채우고 하단 오버레이 패널에 정보.
  //    다른 점은 그 정보가 전부 **입력 가능**하다는 것뿐이다.
  //    (레이아웃을 바꿀 땐 widgets/post_media_hero.dart·post_card.dart 와 맞출 것)

  Widget _editorHero() {
    final color = categoryColor(context, _category);
    // 영상 첨부 시 포스터를 대표 이미지로(포스터 없으면 어두운 타일 + ▶).
    final videoAttached = _uploadedVideo != null;
    final photoUrl = videoAttached
        ? _uploadedVideo!.thumbUrl
        : _uploadedImage?.url;
    final hasPhoto = photoUrl != null || videoAttached;
    final topPad = MediaQuery.paddingOf(context).top;
    final warn = _regionMismatch && _activeMode == 'personal';

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
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
            // 사진 없는 글 — 본문이 곧 히어로다(상세의 블롭 본문과 같은 자리에서
            // 그대로 입력한다).
            if (!hasPhoto)
              Positioned(
                top: topPad + 56 + (warn ? 96 : 0),
                left: 22,
                right: 22,
                bottom: h * 0.42,
                child: Center(child: _contentField(hero: true)),
              ),
            // 영상 첨부 — 중앙 ▶ 배지(피드 카드와 동일 문법).
            if (videoAttached) const Center(child: VideoPlayBadge(size: 56)),
            // 하단 오버레이 패널 — 상세와 동일(뒤에만 점진 블러 + 스크림).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MediaOverlayPanel(
                blurSource: photoUrl == null
                    ? null
                    : Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                blurSourceSize: Size(w, h),
                bottomClearance: MediaQuery.paddingOf(context).bottom + 10,
                clearanceDuration: const Duration(milliseconds: 200),
                child: _overlayEditor(hasPhoto: hasPhoto, color: color),
              ),
            ),
            // 좌상단 — 사진 추가/교체(+제거) 버튼(앱바 높이에 맞춰 정렬).
            Positioned(
              top: topPad + 8,
              left: 12,
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
            // 우상단 — 등록. 앱바 대신 히어로에 직접 얹는다(확장 전환이 안착한
            // 뒤 나타나 모프 중간에 불쑥 뜨지 않게).
            Positioned(
              top: topPad + 8,
              right: 12,
              child: CollapseSettledFade(child: _submitPill()),
            ),
            // 지역 불일치 경고는 개인 글만 — 업체 소식은 사업장 주소 기준.
            if (warn)
              Positioned(
                top: topPad + 60,
                left: 16,
                right: 16,
                child: _RegionWarning(
                  current: _currentDong!,
                  verified: _verifiedDong!,
                ),
              ),
          ],
        );
      },
    );
  }

  /// 하단 오버레이의 입력 묶음 — 피드 카드의 정보 배치를 그대로 따르되
  /// 카테고리·제목·본문·일정·펫을 그 자리에서 편집한다.
  Widget _overlayEditor({required bool hasPhoto, required Color color}) {
    final biz = _activeMode == 'business';
    final me = SessionManager.instance.user;

    return Padding(
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
                              setState(() => _categoryExpanded = false);
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
                                : () =>
                                      setState(() => _categoryExpanded = true),
                            child: _previewPill(
                              text: categoryLabel(_category),
                              textColor: color,
                              trailing: biz ? null : Icons.expand_more,
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
          // 사진 글의 본문 — 카드의 미리보기 두 줄 자리에서 그대로 입력.
          // (사진이 없으면 본문은 화면 중앙 히어로가 맡는다.)
          if (hasPhoto) ...[
            const SizedBox(height: 4),
            _contentField(hero: false),
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
          // 촬영 인증 규칙(1·4·10번째 글) + 선택한 펫별 진행도.
          // 어두운 히어로 위에 얹히므로 흰 필름을 깔아 읽히게 한다.
          if (_isPhotoCategory) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.92),
                child: _PhotoGateNotice(
                  pets: _selectedPets,
                  needsPhoto: _needsPhoto,
                ),
              ),
            ),
          ],
          if (_giveAway) ...[
            const SizedBox(height: 6),
            const Text(
              '분양이 완료되면 소유권이 자동으로 입양자에게 이전돼요',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: Color(0xCCFFFFFF),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 카드의 하트·댓글·조회수 자리 — 작성 중엔 반응 수치가 의미가
          // 없으므로 그 자리에서 연결할 반려동물을 고른다(자유·입양·
          // 소식은 펫이 없어 작성자만 남는다).
          Row(
            children: [
              Text(
                biz ? (_bizName ?? me?.nickname ?? '') : (me?.nickname ?? ''),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xE6FFFFFF),
                ),
              ),
              if (_needsPet) ...[
                const SizedBox(width: 10),
                Expanded(child: _petPicker()),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 본문 입력 — 사진 없는 글은 화면 중앙 히어로(피드 카드의 본문 자리),
  /// 사진 글은 제목 아래 두 줄 미리보기 자리에서 그대로 입력한다.
  // 아래 다섯 조각은 수정 화면(post_edit_screen)과 공용이다 —
  // widgets/post_editor_parts.dart 가 구현이고 여기서는 이 화면의 상태만 엮는다.
  Widget _contentField({required bool hero}) => EditorContentField(
    controller: _contentCtrl,
    hero: hero,
    onChanged: (_) => setState(() {}),
  );

  /// 연결할 반려동물 선택 — 하단 정보 줄에서 가로로 훑어 고른다.
  /// 분양(give_away)은 본인이 소유자인 펫 1마리만.
  Widget _petPicker() {
    if (_loadingPets) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      );
    }
    final pets = _pets.where((p) => !_giveAway || p.role == 'owner').toList();
    if (pets.isEmpty) {
      return Text(
        _giveAway ? '소유자인 반려동물이 없어요' : '반려동물을 먼저 등록해주세요',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, color: Color(0xCCFFFFFF)),
      );
    }
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: pets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(child: _petChip(pets[i], i)),
      ),
    );
  }

  Widget _petChip(MyPet p, int index) {
    final selected = _selectedPetIds.contains(p.id);
    return Entrance(
      index: index,
      offsetY: 8,
      fromScale: 0.9,
      child: Pressable(
        scaleTo: 0.92,
        borderRadius: BorderRadius.circular(100),
        onTap: () => _togglePet(p),
        child: AnimatedContainer(
          duration: MotionDurations.base,
          curve: SpringCurve.standard,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? context.colors.primaryDark
                : Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.pets_outlined,
                size: 13,
                color: selected ? Colors.white : context.colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                p.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : context.colors.textPrimary,
                ),
              ),
              // 이번 글이 인증 순번(1·4·10)이 아닌 펫 — 촬영 없이 게시 가능.
              if (_isPhotoCategory && !p.needsPhotoGate) ...[
                const SizedBox(width: 3),
                Icon(
                  Icons.verified_outlined,
                  size: 12,
                  color: selected
                      ? const Color(0xCCFFFFFF)
                      : context.colors.primaryDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 펫 선택 토글 — 분양은 1마리(단일 선택). 검증 사진이 묶인 펫이 빠지면
  /// 사진·토큰을 무효화한다(다른 아이 사진으로 등록되는 것 방지).
  void _togglePet(MyPet p) {
    setState(() {
      if (_giveAway) {
        if (_selectedPetIds.contains(p.id)) {
          _selectedPetIds.clear();
        } else {
          _selectedPetIds
            ..clear()
            ..add(p.id);
        }
      } else if (_selectedPetIds.contains(p.id)) {
        _selectedPetIds.remove(p.id);
      } else {
        _selectedPetIds.add(p.id);
      }
      if (_photoPetId != null && !_selectedPetIds.contains(_photoPetId)) {
        _uploadedImage = null;
        _photoToken = null;
        _photoPetId = null;
      }
    });
  }

  /// 카드 위 원형 아이콘 버튼(좌상단 사진 컨트롤) — 사진 위 가독용 프로스트.
  Widget _cardIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool busy = false,
  }) => EditorCardIconButton(
    icon: icon,
    tooltip: tooltip,
    onTap: onTap,
    busy: busy,
  );

  /// 카테고리 태그(흰 필름 알약) — 피드 카드와 동일 + 편집 힌트(▾).
  /// [selected] 는 인라인 확장 목록에서 현재 카테고리 강조(색 채움 + 흰 글자).
  Widget _previewPill({
    required String text,
    required Color textColor,
    IconData? trailing,
    bool selected = false,
  }) => EditorCategoryPill(
    text: text,
    textColor: textColor,
    trailing: trailing,
    selected: selected,
  );

  /// 일정 알약 — 피드 카드의 메타 알약과 동일 + 편집 힌트(▾).
  Widget _previewMetaPill({
    required IconData icon,
    required String label,
    bool editable = false,
  }) => EditorMetaPill(icon: icon, label: label, editable: editable);

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
    final mode = await AccountModeRepository.instance.fetchActiveMode();
    if (!mounted) return;
    if (mode == 'business') {
      // 미리보기에 상호를 보여주기 위해 업체 프로필도 로드(실패해도 무해).
      unawaited(
        BusinessProfileRepository.instance
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
  ///    - 선택 펫 중 인증 순번(1·4·10번째 글) 포함 → 직접 촬영(서버 검증)만.
  ///    - 선택 펫이 모두 면제 순번 → 직접 촬영(서버 검증) / 갤러리 불러오기 선택.
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
    if (_selectedPets.any((p) => p.needsPhotoGate)) {
      return _captureAndVerify(); // 인증 순번 펫 포함 → 촬영 인증 필수
    }
    return _choosePhotoSource(); // 모두 면제 순번 → 촬영/갤러리 선택
  }

  /// 면제 순번 펫만 선택된 경우 — 촬영/갤러리 소스 선택 시트.
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
    // OS 픽커가 떠 있는 동안 강제 라우팅(정지 게이트·푸시)으로 라우트가 걷힐 수
    // 있다 — 그러면 아래 setState 가 defunct State 를 건드린다(#238).
    if (file == null || !mounted) return;
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
    if (shot == null || !mounted) return; // 카메라 대기 중 라우트 제거 가능(#238)
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
    final cropped = await Navigator.push<CroppedImage>(
      context,
      AppPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(bytes: raw),
      ),
    );
    if (cropped == null || !mounted) return; // 크롭 화면 대기 중 라우트 제거 가능(#238)
    setState(() {
      _uploadedImage = null;
      _uploadedVideo = null;
      _photoToken = null;
      _photoPetId = null;
      _uploadingImage = true;
    });
    try {
      final up = await StorageService.instance.uploadBytes(
        cropped.bytes,
        category: 'posts',
        ext: cropped.ext,
        mime: cropped.mime,
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
    _scroll.dispose();
    super.dispose();
  }

  /// 등록 — 앱바 자리(우상단)의 알약 버튼. 뒤로가기·제목이 없으므로 화면에서
  /// 유일한 상단 크롬이다.
  Widget _submitPill() => EditorSubmitPill(
    label: '등록',
    enabled: _canSubmit && !_submitting,
    busy: _submitting,
    onTap: _submit,
  );

  @override
  Widget build(BuildContext context) {
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    // 원본(글쓰기 버튼)에서 펼쳐지고, 아래로 쓸어내리면 그 자리로 축소되며
    // 닫힌다 — 게시글 상세와 같은 래퍼(뒤로가기 버튼이 없는 이유).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: CollapsibleView(
        originRect: widget.originRect,
        card: widget.cardBuilder,
        cardRadius: widget.cardRadius,
        // 원본 중심에서 네 변이 동시에 벌어지는 사방 확장(상세와 동일).
        contentAlignment: Alignment.center,
        scrollController: _scroll,
        builder: (context, physics) => Scaffold(
          // 투명 — 축소 전환 중 뒤 커뮤니티가 비친다(CollapseRoute opaque:false).
          backgroundColor: Colors.transparent,
          // 앱바 없음 — 투명 앱바를 두면 그 띠가 히어로 좌상단 사진 버튼의 탭을
          // 가로채 버튼이 죽는다. 등록 버튼은 히어로 안에 직접 얹는다.
          // 화면 = 전체화면 에디터 1장. 스크롤 본문은 없고, 뷰포트 높이짜리
          // 리스트로 CollapsibleView 의 '당겨서 축소' 드래그만 보존한다.
          //
          // 높이는 MediaQuery(창 크기)가 아니라 **실제 본문 제약**에서 받는다 —
          // 웹 셸(AppShell)이 본문을 가운데 컬럼·SafeArea 안으로 밀어넣고,
          // 키보드가 뜨면 Scaffold 가 본문을 줄이므로 창 크기와 어긋난다.
          body: LayoutBuilder(
            builder: (context, box) => ListView(
              controller: _scroll,
              physics: physics,
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: math.max(box.maxHeight, 420),
                  child: _editorHero(),
                ),
              ],
            ),
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

/// 사진 인증 규칙 안내 + 선택한 펫별 진행도.
///
/// 촬영 인증은 **펫마다 1·4·10번째 글에서만** 요구한다(총 3번). 사용자에게
/// 이 규칙이 보이지 않으면 "글 쓸 때마다 매번 찍어야 하나?" 로 읽히므로,
/// 규칙 한 줄 + 지금 선택한 펫이 몇 번째 글인지·다음 인증은 언제인지 함께 보여준다.
/// 규칙은 서버 `app.needs_photo_gate` 와 같다([MyPet.photoGatePostNos]).
class _PhotoGateNotice extends StatelessWidget {
  final List<MyPet> pets;
  final bool needsPhoto;

  const _PhotoGateNotice({required this.pets, required this.needsPhoto});

  /// 펫 한 마리의 진행도 한 줄.
  static String lineFor(MyPet p) {
    final no = p.nextPostNo;
    if (p.needsPhotoGate) {
      return '${p.name} · 이번이 $no번째 글이라 촬영 인증이 필요해요';
    }
    final next = p.nextGatePostNo;
    if (next == null) {
      return '${p.name} · 인증 3번을 모두 마쳤어요. 이제 촬영 없이 올릴 수 있어요';
    }
    return '${p.name} · 이번이 $no번째 글이라 인증 없이 올려요 (다음 인증은 $next번째)';
  }

  @override
  Widget build(BuildContext context) {
    final gateNos = MyPet.photoGatePostNos.join('·');
    final accent = needsPhoto
        ? context.colors.warning
        : context.colors.primaryDark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            needsPhoto ? Icons.photo_camera_outlined : Icons.verified_outlined,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '촬영 인증은 반려동물마다 $gateNos번째 글에만 필요해요',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pets.isEmpty
                      ? '반려동물을 선택하면 이번 글에 인증이 필요한지 알려드려요.'
                      : '세 번을 마치면 그다음부터는 촬영 없이 올릴 수 있어요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                for (final p in pets)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '· ${lineFor(p)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: p.needsPhotoGate
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: p.needsPhotoGate
                            ? context.colors.textPrimary
                            : context.colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (needsPhoto) ...[
                  const SizedBox(height: 4),
                  Text(
                    '카드 좌상단 카메라로 그 아이를 직접 촬영해주세요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
