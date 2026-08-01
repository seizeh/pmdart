import 'package:supabase_flutter/supabase_flutter.dart';
import 'session.dart';

/// 사용자 신고 생성 — reports 테이블에 직접 INSERT.
/// RLS(reports_insert: reporter_id = app.uid())로 본인 신고만 허용된다.
/// 처리/검토는 관리자 RPC(admin_*) 경로에서 이뤄진다.
class ReportRepository {
  ReportRepository._();
  static final ReportRepository instance = ReportRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String? get _uid => SessionManager.instance.user?.id;

  /// 신고 대상 타입 — DB CHECK(reports_target_type_check)와 일치해야 한다.
  static const targetPost = 'post';
  static const targetComment = 'comment';
  static const targetChatMessage = 'chat_message';
  static const targetUser = 'user';

  /// 신고 사유 — DB CHECK(reports_categories_allowed)와 일치해야 한다.
  /// '기타'류 선택 시 [extraDescription] 필수(reports_extra_required).
  /// 일반(댓글/사용자/채팅)용 사유.
  static const categories = <String>[
    '욕설비방',
    '허위정보',
    '사기의심',
    '부적절한내용',
    '약속불이행',
    '기타',
  ];

  /// 게시글 전용 신고 사유.
  static const postCategories = <String>[
    '카테고리와 무관해요',
    '실제 반려동물이 아니에요',
    '기타(직접작성)',
  ];
  static const categoryEtc = '기타';

  /// 대상 타입에 맞는 신고 사유 목록.
  static List<String> categoriesFor(String targetType) =>
      targetType == targetPost ? postCategories : categories;

  /// 상세설명이 필수인 '기타'류 사유인지.
  static bool isEtc(String category) => category.startsWith('기타');

  /// 신고 접수. 카테고리 1개 이상 필수, '기타' 포함 시 설명 필수.
  Future<void> submit({
    required String targetType,
    required String targetId,
    required List<String> selectedCategories,
    String? extraDescription,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('로그인이 필요합니다');
    if (selectedCategories.isEmpty) {
      throw ArgumentError('신고 사유를 1개 이상 선택해주세요');
    }
    final desc = extraDescription?.trim();
    if (selectedCategories.any(isEtc) && (desc == null || desc.isEmpty)) {
      throw ArgumentError("'기타' 선택 시 상세 설명이 필요해요");
    }
    try {
      await _c.from('reports').insert({
        'reporter_id': uid,
        'target_type': targetType,
        'target_id': targetId,
        'categories': selectedCategories,
        if (desc != null && desc.isNotEmpty) 'extra_description': desc,
      });
    } on PostgrestException catch (e) {
      // 중복 방지 인덱스(reports_one_open_per_target) 위반 — 이미 처리 중인 신고가 있음.
      if (e.code == '23505') {
        throw StateError('이미 신고한 대상이에요. 검토가 진행 중입니다');
      }
      rethrow;
    }
  }

  /// 사용자 차단 — `block_user` RPC 가 차단과 **신고를 함께** 남긴다.
  ///
  /// 신고를 함께 남기는 것은 App Store 1.2 요구사항이다("차단은 개발자에게
  /// 통보되어야 한다"). 차단당한 사람의 글은 서버 뷰(`v_post_feed`)가 즉시
  /// 걸러내므로 클라이언트는 목록만 새로 받으면 된다.
  ///
  /// 같은 사람을 다시 차단해도 안전하다(중복 차단·중복 신고 모두 무시).
  Future<void> block(String userId, {String? reason}) async {
    if (_uid == null) throw StateError('로그인이 필요합니다');
    await _c.rpc(
      'block_user',
      params: {'p_blocked': userId, 'p_reason': reason},
    );
  }
}
