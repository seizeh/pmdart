import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/business_repository.dart';
import '../services/juso_service.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';

/// 업체(사업자) 등록 — 가입 직후·내정보 수정 양쪽에서 진입 (0025 §7.1).
///
/// 입력 순서: ① 사업자번호(즉시 국세청 확인) → ② 업종 → ③ 상호 → ④ 주소검색
/// → ⑤ 업장 전화 → ⑥ 연락 이메일 → ⑦ 등록증 업로드 → 제출.
/// 사업장명·이전 상호명·추가 서류는 기본 접힘(해당자만 펼침).
/// 제출 시 서버가 국세청 재조회 + 공공데이터(facilities) 대조로 자동승인/심사 분기.
class BusinessRegisterScreen extends StatefulWidget {
  const BusinessRegisterScreen({super.key});

  @override
  State<BusinessRegisterScreen> createState() => _BusinessRegisterScreenState();
}

class _BusinessRegisterScreenState extends State<BusinessRegisterScreen> {
  // 기존 신청 상태 (pending/approved 면 폼 대신 상태 화면)
  bool _loadingProfile = true;
  BusinessProfile? _mine;

  // ① 사업자번호 + 국세청 확인
  final _bNoCtrl = TextEditingController();
  bool _checkingBno = false;
  bool _bnoOk = false; // 계속사업자(01) 확인됨
  String? _bnoMsg;

  // ② 업종
  String? _category;

  // ③ 상호 (+접힘: 사업장명 / 이전 상호)
  final _nameCtrl = TextEditingController();
  bool _storefrontDiffers = false;
  final _storefrontCtrl = TextEditingController();
  bool _renamed = false;
  final _prevNameCtrl = TextEditingController();

  // ④ 주소 — juso 검색 결과(키 미설정 시 수동 입력 폴백)
  JusoAddress? _address;
  final _manualAddrCtrl = TextEditingController();

  // ⑤ 전화 ⑥ 이메일 (대표자명은 선택)
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _repCtrl = TextEditingController();

  // ⑦ 서류
  PickedDoc? _license;
  bool _hasExtraDoc = false;
  PickedDoc? _extraDoc;

  bool _submitting = false;

  // 업체 정보는 가입 동의 범위 밖(신청 시점 수집)이라 별도 필수 동의를 받는다 (처리방침 §1·§3)
  bool _agreeCollect = false;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
    _bNoCtrl.dispose();
    _nameCtrl.dispose();
    _storefrontCtrl.dispose();
    _prevNameCtrl.dispose();
    _manualAddrCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _repCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    final mine = await BusinessRepository.instance.fetchMine();
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _loadingProfile = false;
      // 반려 후 재신청: 기존 입력 프리필 (서류는 다시 첨부)
      if (mine != null && mine.isRejected) {
        _bNoCtrl.text = mine.businessRegNo;
        _category = mine.declaredCategory;
        _nameCtrl.text = mine.businessName;
        if ((mine.storefrontName ?? '').isNotEmpty) {
          _storefrontDiffers = true;
          _storefrontCtrl.text = mine.storefrontName!;
        }
        if ((mine.prevBusinessName ?? '').isNotEmpty) {
          _renamed = true;
          _prevNameCtrl.text = mine.prevBusinessName!;
        }
        _manualAddrCtrl.text = mine.businessAddress;
        _phoneCtrl.text = mine.businessPhone ?? '';
        _emailCtrl.text = mine.contactEmail;
      }
    });
  }

  // ── 진행률: 완료된 입력 섹션 수 (0025 §7.1 — 심리적 완주 유도) ──
  int get _doneCount {
    var n = 0;
    if (_bnoOk) n++;
    if (_category != null) n++;
    if (_nameCtrl.text.trim().isNotEmpty) n++;
    if (_hasAddress) n++;
    if (_phoneCtrl.text.trim().isNotEmpty) n++;
    if (_emailRe.hasMatch(_emailCtrl.text.trim())) n++;
    if (_license != null) n++;
    return n;
  }

  bool get _hasAddress =>
      _address != null || _manualAddrCtrl.text.trim().isNotEmpty;

  bool get _canSubmit => _doneCount == 7 && _agreeCollect && !_submitting;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.cream,
      appBar: AppBar(
        backgroundColor: context.colors.cream,
        title: const Text('업체 등록'),
      ),
      body: SafeArea(
        child: _loadingProfile
            ? const Center(child: CircularProgressIndicator())
            : switch (_mine?.status) {
                'pending' => _StatusView(
                  icon: Icons.hourglass_top_rounded,
                  title: '심사가 진행 중이에요',
                  message: _mine!.reviewTrack == 'new_business'
                      ? '공공데이터에 아직 없는 새 업체라 관리자가 서류를 확인하고 있어요.\n결과는 알림으로 알려드릴게요.'
                      : '입력하신 정보를 확인하고 있어요.\n결과는 알림으로 알려드릴게요.',
                  profile: _mine!,
                ),
                // 승인 후 관리는 공용 패널 — 업체 모드의 내정보(업체 관리) 최상단에도
                // 동일 패널이 인라인된다(한 번의 탭으로 수정 도달).
                'approved' => ListView(
                  padding: const EdgeInsets.all(24),
                  children: const [BusinessManagePanel()],
                ),
                _ => _form(), // 미신청 또는 반려(재신청)
              },
      ),
    );
  }

  // ── 신청 폼 ──

  Widget _form() {
    final rejected = _mine?.isRejected == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: _SegmentBar(done: _doneCount, total: 7),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rejected) _rejectedBanner(),
                _sectionTitle('사업자등록번호'),
                _bnoField(),
                if (_bnoMsg != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _bnoMsg!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _bnoOk
                          ? context.colors.primaryDark
                          : context.colors.textSecondary,
                    ),
                  ),
                ],
                _sectionTitle('업종'),
                Text(
                  '사업자등록증의 업태·종목을 확인하고 실제 등록된 업종을 선택해 주세요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (key, label) in businessCategories)
                      ChoiceChip(
                        label: Text(label),
                        selected: _category == key,
                        onSelected: (_) => setState(() => _category = key),
                      ),
                  ],
                ),
                _sectionTitle('상호명'),
                TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '사업자등록증에 기재된 상호',
                  ),
                ),
                const SizedBox(height: 8),
                _foldToggle(
                  '사업장명(간판명)이 상호와 다른가요?',
                  _storefrontDiffers,
                  (v) => setState(() => _storefrontDiffers = v),
                ),
                if (_storefrontDiffers) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _storefrontCtrl,
                    decoration: const InputDecoration(
                      hintText: '간판에 쓰는 이름 (예: 행복동물병원)',
                    ),
                  ),
                ],
                _foldToggle(
                  '상호를 변경한 적이 있나요?',
                  _renamed,
                  (v) => setState(() => _renamed = v),
                ),
                if (_renamed) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _prevNameCtrl,
                    decoration: const InputDecoration(
                      hintText: '이전 상호명 — 공공데이터가 이전 이름일 수 있어요',
                    ),
                  ),
                ],
                _sectionTitle('사업장 주소'),
                _addressField(),
                _sectionTitle('사업장 전화'),
                Text(
                  '영업 인허가 시 등록한 업장 전화를 입력해 주세요 (유선 가능, 예: 031-123-4567).',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\-]')),
                    LengthLimitingTextInputFormatter(13),
                  ],
                  decoration: const InputDecoration(hintText: '0311234567'),
                ),
                _sectionTitle('연락받을 이메일'),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'example@pawmate.kr',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _repCtrl,
                  decoration: const InputDecoration(
                    labelText: '대표자명 (선택)',
                    hintText: '심사에 참고돼요',
                  ),
                ),
                _sectionTitle('사업자등록증'),
                _docPicker(
                  picked: _license,
                  label: '사업자등록증 첨부',
                  onPick: (d) => setState(() => _license = d),
                ),
                const SizedBox(height: 6),
                Text(
                  '✓ 휴대폰으로 찍은 사진도 괜찮아요   ✓ PDF도 가능해요',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _foldToggle(
                  '추가 서류가 있나요? (신규 개업 업체)',
                  _hasExtraDoc,
                  (v) => setState(() => _hasExtraDoc = v),
                ),
                if (_hasExtraDoc) ...[
                  const SizedBox(height: 4),
                  Text(
                    '최근 개업해서 공공데이터에 없는 업체는 영업 등록증(병원은 개설신고확인증)을 함께 첨부하면 심사가 빨라요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _docPicker(
                    picked: _extraDoc,
                    label: '영업 등록증 등 첨부',
                    onPick: (d) => setState(() => _extraDoc = d),
                  ),
                ],
                const SizedBox(height: 20),
                _foldToggle(
                  '[필수] 업체 인증 심사를 위한 개인정보 수집·이용에 동의합니다',
                  _agreeCollect,
                  (v) => setState(() => _agreeCollect = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Text(
                    '항목: 사업자등록번호·상호·업종·사업장 주소·전화·이메일·증빙 서류 · '
                    '목적: 사업자 상태 확인 및 인증 심사 · '
                    '보유: 승인 시 인증 유지 기간, 반려 시 6개월, 탈퇴 시 30일 후 파기. '
                    '자세한 내용은 개인정보 처리방침을 확인해주세요.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: context.colors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: context.colors.textOnPrimary,
                      ),
                    )
                  : Text(rejected ? '다시 신청하기' : '등록 신청'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rejectedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이전 신청이 반려되었어요',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '사유: ${_mine?.rejectedReason ?? '-'}',
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: context.colors.textPrimary,
      ),
    ),
  );

  Widget _foldToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: value
                  ? context.colors.primary
                  : context.colors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ① 사업자번호: 10자리 완성 + 체크섬 통과 시 즉시 국세청 확인 ──

  Widget _bnoField() {
    return TextField(
      controller: _bNoCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      onChanged: (v) {
        if (_bnoOk || _bnoMsg != null) {
          setState(() {
            _bnoOk = false;
            _bnoMsg = null;
          });
        }
        if (v.length == 10) _checkBno(v);
      },
      decoration: InputDecoration(
        hintText: '숫자 10자리',
        suffixIcon: _checkingBno
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _bnoOk
            ? Icon(Icons.check_circle, color: context.colors.primary)
            : null,
      ),
    );
  }

  static bool _validBizNoChecksum(String no) {
    if (no.length != 10) return false;
    const w = [1, 3, 7, 1, 3, 7, 1, 3, 5];
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(no[i]) * w[i];
    }
    sum += (int.parse(no[8]) * 5) ~/ 10;
    return (10 - (sum % 10)) % 10 == int.parse(no[9]);
  }

  Future<void> _checkBno(String no) async {
    if (!_validBizNoChecksum(no)) {
      setState(() => _bnoMsg = '번호를 다시 확인해주세요 (자릿수 검증 실패)');
      return;
    }
    setState(() {
      _checkingBno = true;
      _bnoMsg = null;
    });
    final r = await BusinessRepository.instance.checkBusinessNo(no);
    if (!mounted || _bNoCtrl.text != no) return;
    setState(() {
      _checkingBno = false;
      _bnoOk = r.ok;
      _bnoMsg = r.ok
          ? '✓ 계속사업자 확인됨'
          : switch (r.statusCode) {
              '02' => '휴업 상태의 사업자번호는 등록할 수 없어요',
              '03' => '폐업 상태의 사업자번호는 등록할 수 없어요',
              _ => r.error == 'nts_unavailable' || r.error == 'network'
                  ? '국세청 확인에 실패했어요. 잠시 후 다시 시도해주세요'
                  : '국세청에 등록되지 않은 사업자번호예요',
            };
    });
  }

  // ── ④ 주소: juso 검색(키 있으면) / 수동 입력 폴백 ──

  Widget _addressField() {
    if (!JusoService.instance.enabled) {
      return TextField(
        controller: _manualAddrCtrl,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: '사업자등록증의 사업장 소재지 (도로명 주소)',
        ),
      );
    }
    return InkWell(
      onTap: _openAddressSearch,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: context.colors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _address?.roadAddr ?? '주소 검색 (탭해서 찾기)',
                style: TextStyle(
                  fontSize: 14,
                  color: _address == null
                      ? context.colors.textTertiary
                      : context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddressSearch() async {
    final picked = await showModalBottomSheet<JusoAddress>(
      context: context,
      isScrollControlled: true,
      // 키보드가 올라오면 시트가 풀높이까지 자랄 수 있다 — 상태바(시계) 아래로
      // 파고들지 않게 세이프에어리어를 지킨다.
      useSafeArea: true,
      backgroundColor: context.colors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddressSearchSheet(),
    );
    if (picked != null && mounted) setState(() => _address = picked);
  }

  // ── ⑦ 서류 선택 ──

  Widget _docPicker({
    required PickedDoc? picked,
    required String label,
    required ValueChanged<PickedDoc> onPick,
  }) {
    return OutlinedButton.icon(
      onPressed: () async {
        final d = await _pickDoc();
        if (d != null) onPick(d);
      },
      icon: Icon(picked == null ? Icons.upload_file : Icons.check_circle),
      label: Text(
        picked == null ? label : picked.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }

  /// 서류 선택 방식: 갤러리 사진(휴대폰 촬영본) 또는 파일(PDF 등).
  Future<PickedDoc?> _pickDoc() async {
    final src = await showModalBottomSheet<_DocSource>(
      context: context,
      backgroundColor: context.colors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: sheetCtx.colors.textPrimary,
              ),
              title: const Text('갤러리에서 사진 선택'),
              subtitle: const Text('휴대폰으로 찍은 등록증 사진'),
              onTap: () => Navigator.pop(sheetCtx, _DocSource.gallery),
            ),
            ListTile(
              leading: Icon(
                Icons.upload_file,
                color: sheetCtx.colors.textPrimary,
              ),
              title: const Text('파일 선택'),
              subtitle: const Text('PDF 또는 이미지 파일'),
              onTap: () => Navigator.pop(sheetCtx, _DocSource.file),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    return switch (src) {
      _DocSource.gallery => StorageService.instance.pickDocumentFromGallery(),
      _DocSource.file => StorageService.instance.pickDocument(),
      null => Future.value(),
    };
  }

  // ── 제출 ──

  Future<void> _submit() async {
    setState(() => _submitting = true);
    // 업로드는 제출 시점에 — 미제출 이탈 시 고아 파일을 만들지 않는다.
    String licensePath;
    String? extraPath;
    try {
      licensePath = await StorageService.instance.uploadBusinessDoc(
        _license!,
        kind: 'license',
      );
      if (_hasExtraDoc && _extraDoc != null) {
        extraPath = await StorageService.instance.uploadBusinessDoc(
          _extraDoc!,
          kind: 'extra',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('서류 업로드에 실패했어요. 네트워크를 확인해주세요');
      return;
    }

    final r = await BusinessRepository.instance.apply(
      bNo: _bNoCtrl.text,
      category: _category!,
      businessName: _nameCtrl.text.trim(),
      storefrontName: _storefrontDiffers ? _storefrontCtrl.text.trim() : null,
      prevBusinessName: _renamed ? _prevNameCtrl.text.trim() : null,
      addressRoad: _address?.roadAddr ?? _manualAddrCtrl.text.trim(),
      addressJibun: _address?.jibunAddr,
      regionCode: _address?.admCd,
      phone: _phoneCtrl.text,
      repName: _repCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      licensePath: licensePath,
      extraDocPath: extraPath,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (r.ok) {
      if (r.status == 'approved') {
        _toast('업체 인증이 완료되었어요! 내정보 수정에서 업체 모드로 전환할 수 있어요');
      } else {
        _toast(
          r.track == 'new_business'
              ? '신청이 접수되었어요. 새 업체라 관리자가 서류를 확인할 거예요'
              : '신청이 접수되었어요. 심사 결과를 알림으로 알려드릴게요',
        );
      }
      await _loadMine(); // pending/approved 상태 화면으로 전환
      return;
    }

    switch (r.errorCode) {
      case 'extra_doc_required':
        // 공공데이터 미조회 → 추가 서류 섹션 자동 펼침 (0025 §7.1)
        setState(() => _hasExtraDoc = true);
        _toast('공공데이터에서 업체를 찾지 못했어요. 영업 등록증 등 추가 서류를 첨부해주세요');
      case 'business_no_taken':
        _toast('이미 다른 계정에서 사용 중인 사업자등록번호예요');
      case 'facility_taken':
        _toast('이미 다른 계정이 이 업소로 등록되어 있어요. 본인 업소라면 고객센터로 알려주세요');
      case 'already_pending':
        _toast('이미 심사가 진행 중이에요');
        await _loadMine();
      case 'already_approved':
        _toast('이미 인증된 업체예요');
        await _loadMine();
      case 'nts_not_active':
        _toast('휴·폐업 상태의 사업자번호는 등록할 수 없어요');
      case 'rate_limited':
        _toast('요청이 너무 잦아요. 잠시 후 다시 시도해주세요');
      default:
        _toast('신청에 실패했어요. 잠시 후 다시 시도해주세요');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

// ── 진행률 게이지 — 가입 화면 단계 바와 동일 언어(0025 §7.1) ──

class _SegmentBar extends StatelessWidget {
  final int done;
  final int total;
  const _SegmentBar({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(total, (i) {
              final active = i < done;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active
                        ? context.colors.primary
                        : context.colors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$done / $total',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── 신청 상태 화면 (pending / approved) ──

class _StatusView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final BusinessProfile profile;
  const _StatusView({
    required this.icon,
    required this.title,
    required this.message,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    // 대표 사진·버튼이 늘어나 화면을 넘칠 수 있다 — 스크롤 가능한 리스트로
    // (Column 고정 배치는 사진 설정 시 오버플로우, #83 후속 버그 수정).
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
          const SizedBox(height: 8),
          Icon(icon, size: 56, color: context.colors.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.border, width: 0.5),
            ),
            child: Column(
              children: [
                _row(context, '상호', profile.businessName),
                if ((profile.storefrontName ?? '').isNotEmpty)
                  _row(context, '사업장명', profile.storefrontName!),
                _row(context, '업종',
                    businessCategoryLabel(profile.declaredCategory)),
                _row(context, '사업자번호', _maskBno(profile.businessRegNo)),
                _row(context, '주소', profile.businessAddress),
                _row(context, '이메일', profile.contactEmail),
              ],
            ),
          ),
      ],
    );
  }

  // 사업자번호는 상태 화면에서 일부 마스킹 (전체는 본인이 이미 아는 값)
  static String _maskBno(String no) => no.length == 10
      ? '${no.substring(0, 3)}-${no.substring(3, 5)}-***${no.substring(8)}'
      : no;

  Widget _row(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            k,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(
              fontSize: 13.5,
              color: context.colors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── 대표 사진 위치 조절 — 지도 상세 히어로와 동일한 프레임으로 미리보기 ──

class _PhotoAlignSheet extends StatefulWidget {
  final ImageProvider image;
  final double initial;
  final String name; // 미리보기에 얹을 상호(실제 상세 화면 재현)
  const _PhotoAlignSheet({
    required this.image,
    required this.initial,
    required this.name,
  });

  @override
  State<_PhotoAlignSheet> createState() => _PhotoAlignSheetState();
}

class _PhotoAlignSheetState extends State<_PhotoAlignSheet> {
  late double _alignY = widget.initial.clamp(-1.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 20, 20, 20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '사진 위치 조절',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '사진을 위아래로 움직여 지도 상세에서 보일 영역을 정해주세요. 아래 화면이 실제로 보이는 모습이에요.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            // 드래그 방향과 사진 이동이 일치하게: 아래로 끌면 사진이 내려가
            // 윗부분이 보인다(align -1 방향).
            onVerticalDragUpdate: (d) => setState(() {
              _alignY = (_alignY - d.delta.dy / 120).clamp(-1.0, 1.0);
            }),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 240, // 지도 상세 히어로와 동일 높이
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: widget.image,
                      fit: BoxFit.cover,
                      alignment: Alignment(0, _alignY),
                    ),
                    // 실제 상세와 동일한 하단 스크림 + 정보 자리 미리보기.
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 120,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x59000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 17,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _alignY),
                  child: const Text('이 위치로 저장'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 서류 선택 경로 — 갤러리 사진 / 파일 브라우저.
enum _DocSource { gallery, file }

// ── juso 주소검색 바텀시트 ──

class AddressSearchSheet extends StatefulWidget {
  const AddressSearchSheet({super.key});

  @override
  State<AddressSearchSheet> createState() => AddressSearchSheetState();
}

class AddressSearchSheetState extends State<AddressSearchSheet> {
  final _ctrl = TextEditingController();
  List<JusoAddress> _results = const [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) return;
    setState(() => _searching = true);
    final r = await JusoService.instance.search(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searched = true;
      _results = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '사업장 주소 검색',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: '도로명, 건물명 또는 지번',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                // 테마 기본 minimumSize(Size.fromHeight)는 최소 폭이 무한이라
                // Row(무한 폭 제약) 안에서는 레이아웃이 터진다 — 폭을 명시.
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: _searching ? null : _search,
                child: const Text('검색'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: _searching
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _searched ? '검색 결과가 없어요' : '주소를 검색해주세요',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: context.colors.border),
                    itemBuilder: (context, i) {
                      final a = _results[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          a.roadAddr,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          a.jibunAddr,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textTertiary,
                          ),
                        ),
                        onTap: () => Navigator.pop(context, a),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}


/// 승인 업체 관리 패널 — 업체 정보 요약·수정, 대표 사진 설정/위치 조절/제거.
/// BusinessRegisterScreen(승인 상태)과 업체 모드의 내정보(업체 관리) 최상단에서
/// 공용 — "프로필 한 번 탭으로 수정 도달" 요구의 구현체.
class BusinessManagePanel extends StatefulWidget {
  const BusinessManagePanel({super.key});

  @override
  State<BusinessManagePanel> createState() => _BusinessManagePanelState();
}

class _BusinessManagePanelState extends State<BusinessManagePanel> {
  BusinessProfile? _mine;
  bool _loading = true;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  Future<void> _loadMine() async {
    final mine = await BusinessRepository.instance.fetchMine();
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    final mine = _mine;
    if (mine == null || !mine.isApproved) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.verified, size: 18, color: context.colors.primaryDark),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mine.storefrontName ?? mine.businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border, width: 0.5),
          ),
          child: Column(
            children: [
              _row(context, '상호', mine.businessName),
              if ((mine.storefrontName ?? '').isNotEmpty)
                _row(context, '사업장명', mine.storefrontName!),
              _row(context, '업종', businessCategoryLabel(mine.declaredCategory)),
              _row(context, '주소', mine.businessAddress),
              if ((mine.businessPhone ?? '').isNotEmpty)
                _row(context, '전화', mine.businessPhone!),
              if ((mine.businessHours ?? '').isNotEmpty)
                _row(context, '영업시간', mine.businessHours!),
              _row(context, '이메일', mine.contactEmail),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '대표 사진',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '업체 프로필과 지도 상세에 쓰이는 사진이에요.',
            style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
          ),
        ),
        const SizedBox(height: 8),
        if (mine.photoUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 140,
              child: Image.network(
                mine.photoUrl!,
                fit: BoxFit.cover,
                alignment: Alignment(0, mine.photoAlignY),
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: context.colors.surfaceMuted),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickAndSetPhoto,
                icon: const Icon(Icons.photo_outlined, size: 18),
                label: Text(mine.photoUrl == null ? '사진 설정' : '사진 변경'),
              ),
            ),
            if (mine.photoUrl != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _adjustPhoto,
                  icon: const Icon(Icons.open_with, size: 18),
                  label: const Text('위치 조절'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _removePhoto,
                tooltip: '사진 제거',
                icon: Icon(Icons.delete_outline, color: context.colors.danger),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openInfoEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('업체 정보 수정'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            k,
            style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(fontSize: 13.5, color: context.colors.textPrimary),
          ),
        ),
      ],
    ),
  );

  Future<void> _pickAndSetPhoto() async {
    final mine = _mine;
    if (mine == null) return;
    final file = await StorageService.instance.pickImage();
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final align = await _openAlignSheet(
      image: MemoryImage(bytes),
      initial: 0,
      name: mine.storefrontName ?? mine.businessName,
    );
    if (align == null || !mounted) return;
    try {
      final up = await StorageService.instance.upload(
        file,
        category: 'business',
      );
      final ok = await BusinessRepository.instance.setPhoto(
        url: up.url,
        alignY: align,
      );
      if (!mounted) return;
      _toast(ok ? '대표 사진을 설정했어요 — 지도 상세에 바로 반영돼요' : '설정에 실패했어요');
      if (ok) await _loadMine();
    } catch (_) {
      if (mounted) _toast('사진 업로드에 실패했어요. 네트워크를 확인해주세요');
    }
  }

  /// 기존 사진의 위치(세로 초점)만 다시 조절.
  Future<void> _adjustPhoto() async {
    final mine = _mine;
    if (mine?.photoUrl == null) return;
    final align = await _openAlignSheet(
      image: NetworkImage(mine!.photoUrl!),
      initial: mine.photoAlignY,
      name: mine.storefrontName ?? mine.businessName,
    );
    if (align == null || !mounted) return;
    final ok = await BusinessRepository.instance.setPhoto(
      url: mine.photoUrl,
      alignY: align,
    );
    if (!mounted) return;
    _toast(ok ? '사진 위치를 저장했어요' : '저장에 실패했어요');
    if (ok) await _loadMine();
  }

  Future<void> _removePhoto() async {
    final ok = await BusinessRepository.instance.setPhoto(url: null);
    if (!mounted) return;
    _toast(ok ? '대표 사진을 제거했어요' : '제거에 실패했어요');
    if (ok) await _loadMine();
  }

  Future<double?> _openAlignSheet({
    required ImageProvider image,
    required double initial,
    required String name,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PhotoAlignSheet(image: image, initial: initial, name: name),
    );
  }

  Future<void> _openInfoEdit() async {
    final mine = _mine;
    if (mine == null) return;
    final nameCtrl = TextEditingController(
      text: mine.storefrontName ?? mine.businessName,
    );
    final phoneCtrl = TextEditingController(text: mine.businessPhone ?? '');
    final emailCtrl = TextEditingController(text: mine.contactEmail);
    final hoursCtrl = TextEditingController(text: mine.businessHours ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '업체 정보 수정',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: sheetCtx.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '간판명·전화·영업시간은 지도 시설 정보에도 바로 반영돼요. 사업자번호·주소·업종 변경은 재인증이 필요해요.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: sheetCtx.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '사업장명(간판명)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\-]')),
                LengthLimitingTextInputFormatter(13),
              ],
              decoration: const InputDecoration(labelText: '업장 전화'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '연락받을 이메일'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: hoursCtrl,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              decoration: const InputDecoration(
                labelText: '영업시간',
                hintText: '예: 매일 10:00 - 20:00 (월 휴무)',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetCtx, true),
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final email = emailCtrl.text.trim();
    if (email.isNotEmpty && !_emailRe.hasMatch(email)) {
      _toast('이메일 형식을 확인해주세요');
      return;
    }
    // 영업시간은 비워서 저장하면 삭제(서버: 빈 문자열 → null).
    final ok = await BusinessRepository.instance.updateMyInfo(
      storefrontName: nameCtrl.text.trim(),
      phone: phoneCtrl.text,
      email: email,
      hours: hoursCtrl.text,
    );
    if (!mounted) return;
    _toast(ok ? '저장했어요 — 지도 정보에도 반영됐어요' : '저장에 실패했어요. 잠시 후 다시 시도해주세요');
    if (ok) await _loadMine();
  }
}
