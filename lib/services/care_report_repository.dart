import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session.dart';

/// 케어 리포트(0028 P1 — 미용 전후 사진) 데이터 접근.
/// 발행은 has_license('grooming') 게이트가 서버에서 재검증한다.
class CareReportRepository {
  CareReportRepository._();
  static final CareReportRepository instance = CareReportRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 발행 — 성공 시 공유 토큰, 실패 시 에러 코드
  /// (license_required / invalid_pet_label / invalid_photos / invalid_phone / network).
  /// [recipientPhone] 은 선택 — 넣으면 손님 가입 시 자동 연결(0028 §4.2).
  Future<({String? token, String? error})> create({
    required String petLabel,
    required List<String> photoUrls,
    String? note,
    String? recipientPhone,
  }) async {
    if (SessionManager.instance.user == null) {
      return (token: null, error: 'auth');
    }
    try {
      final res = await _c.rpc(
        'create_care_report',
        params: {
          'p_pet_label': petLabel.trim(),
          'p_photos': photoUrls,
          'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
          'p_recipient_phone': (recipientPhone ?? '').trim().isEmpty
              ? null
              : recipientPhone!.trim(),
        },
      );
      final token = (res as Map<String, dynamic>)['token'] as String?;
      return (token: token, error: token == null ? 'network' : null);
    } on PostgrestException catch (e) {
      const codes = [
        'license_required',
        'invalid_pet_label',
        'invalid_photos',
        'invalid_phone',
      ];
      for (final c in codes) {
        if (e.message.contains(c)) return (token: null, error: c);
      }
      return (token: null, error: 'network');
    } catch (_) {
      return (token: null, error: 'network');
    }
  }

  /// 내가 발행한 리포트(업체) — 수령자 연결 상태 표시용.
  Future<List<IssuedCareReport>> fetchMine() async {
    try {
      final rows = await _c.rpc('my_care_reports', params: {'p_limit': 50});
      return (rows as List)
          .map((r) => IssuedCareReport.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 내가 받은 리포트(보호자).
  Future<List<ReceivedCareReport>> fetchReceived() async {
    try {
      final rows = await _c.rpc(
        'my_received_care_reports',
        params: {'p_limit': 50},
      );
      return (rows as List)
          .map((r) => ReceivedCareReport.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 전화번호 대조 자동 연결(0028 §4.2) — 앱 시작·가입 직후 호출.
  /// 연결 건수 반환(알림은 서버가 발송). 실패는 조용히 0(다음 시작 때 재시도).
  Future<int> claim() async {
    if (SessionManager.instance.user == null) return 0;
    try {
      final n = await _c.rpc('claim_care_reports');
      return (n as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('케어 리포트 claim 실패(무해 — 다음 시작 때 재시도): $e');
      return 0;
    }
  }
}

/// 발행한 리포트 1건 (my_care_reports RPC 기준).
class IssuedCareReport {
  final String id;
  final String petLabel;
  final List<String> photos;
  final String? note;
  final DateTime? createdAt;
  final String? claimedNickname; // null = 미연결
  final String? token;
  final DateTime? expiresAt;
  final int viewCount;

  const IssuedCareReport({
    required this.id,
    required this.petLabel,
    required this.photos,
    this.note,
    this.createdAt,
    this.claimedNickname,
    this.token,
    this.expiresAt,
    this.viewCount = 0,
  });

  factory IssuedCareReport.fromJson(Map<String, dynamic> j) => IssuedCareReport(
    id: (j['id'] ?? '') as String,
    petLabel: (j['pet_label'] ?? '') as String,
    photos: [for (final u in (j['photos'] as List? ?? const [])) u.toString()],
    note: j['note'] as String?,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
    claimedNickname: j['claimed_nickname'] as String?,
    token: j['token'] as String?,
    expiresAt: DateTime.tryParse((j['expires_at'] ?? '') as String)?.toLocal(),
    viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
  );
}

/// 받은 리포트 1건 (my_received_care_reports RPC 기준).
class ReceivedCareReport {
  final String id;
  final String kind; // grooming | boarding
  final String petLabel;
  final List<String> photos;
  final String? note;
  final DateTime? createdAt;
  final String? businessName;

  const ReceivedCareReport({
    required this.id,
    required this.kind,
    required this.petLabel,
    required this.photos,
    this.note,
    this.createdAt,
    this.businessName,
  });

  factory ReceivedCareReport.fromJson(
    Map<String, dynamic> j,
  ) => ReceivedCareReport(
    id: (j['id'] ?? '') as String,
    kind: (j['kind'] ?? 'grooming') as String,
    petLabel: (j['pet_label'] ?? '') as String,
    photos: [for (final u in (j['photos'] as List? ?? const [])) u.toString()],
    note: j['note'] as String?,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
    businessName: j['business_name'] as String?,
  );
}
