import 'package:supabase_flutter/supabase_flutter.dart';

/// 접종 리마인더(0028 P3 — 분양 스타터) 데이터 접근.
/// 일정 콘텐츠는 앱(utils/vaccination_schedule.dart)이 계산하고,
/// 서버는 저장·크론 알림(vaccine_reminder)만 담당한다. 보호자(pet_guardians)
/// 여부는 서버가 재검증한다('not_guardian').
class VaccinationRepository {
  VaccinationRepository._();
  static final VaccinationRepository instance = VaccinationRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 펫의 접종 일정(날짜순). 실패 시 null — 빈 목록(미등록)과 구분한다.
  Future<List<VaccinationEvent>?> fetchEvents(String petId) async {
    try {
      final rows = await _c.rpc('my_vaccination_events', params: {
        'p_pet': petId,
      });
      return (rows as List)
          .map((r) => VaccinationEvent.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 일정 저장 — 미완료분을 통째로 교체(완료 체크는 서버가 보존).
  /// [source] 는 퍼널 계측용('onboarding' | 'manage').
  /// 성공 시 저장 건수, 실패 시 에러 코드(not_guardian / invalid_events / network).
  Future<({int? count, String? error})> setSchedule({
    required String petId,
    required List<({String label, DateTime dueDate})> events,
    String? source,
  }) async {
    try {
      final res = await _c.rpc('set_vaccination_schedule', params: {
        'p_pet': petId,
        'p_events': [
          for (final e in events)
            {'label': e.label, 'due_date': _dateOnly(e.dueDate)},
        ],
        'p_source': source,
      });
      return (count: (res as num?)?.toInt() ?? 0, error: null);
    } on PostgrestException catch (e) {
      const codes = ['not_guardian', 'invalid_events', 'invalid_source'];
      for (final c in codes) {
        if (e.message.contains(c)) return (count: null, error: c);
      }
      return (count: null, error: 'network');
    } catch (_) {
      return (count: null, error: 'network');
    }
  }

  /// 완료 체크 토글. 성공 여부 반환(실패 시 UI 는 원복).
  Future<bool> setDone(String eventId, bool done) async {
    try {
      final res = await _c.rpc('set_vaccination_done', params: {
        'p_event': eventId,
        'p_done': done,
      });
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 접종 일정 1건 (my_vaccination_events RPC 기준).
class VaccinationEvent {
  final String id;
  final String label;
  final DateTime dueDate;
  final DateTime? doneAt;

  const VaccinationEvent({
    required this.id,
    required this.label,
    required this.dueDate,
    this.doneAt,
  });

  bool get done => doneAt != null;

  VaccinationEvent copyWith({DateTime? doneAt, bool clearDone = false}) =>
      VaccinationEvent(
        id: id,
        label: label,
        dueDate: dueDate,
        doneAt: clearDone ? null : (doneAt ?? this.doneAt),
      );

  factory VaccinationEvent.fromJson(Map<String, dynamic> j) =>
      VaccinationEvent(
        id: (j['id'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        dueDate: DateTime.parse((j['due_date'] ?? '') as String),
        doneAt:
            DateTime.tryParse((j['done_at'] ?? '') as String)?.toLocal(),
      );
}
