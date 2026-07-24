/// 분양 스타터(0028 P3) — 표준 접종 일정 콘텐츠.
///
/// 일정 콘텐츠는 앱이 계산하고, 서버(app.vaccination_events)는 저장·알림만
/// 담당한다. 생년월일 + 종(강아지/고양이) 기준의 일반적인 표준 주령표이며,
/// 정확한 접종 시기는 동물병원과 상의해야 한다(화면에 면책 문구 표기).
library;

/// 제안 접종 일정 1건 — 라벨 + 예정일(생후 주령 기준 계산).
class SuggestedVaccination {
  final String label;
  final DateTime dueDate;

  const SuggestedVaccination({required this.label, required this.dueDate});
}

/// 강아지 표준 일정 — (생후 주령, 라벨).
const _dogPlan = <(int, String)>[
  (6, '종합백신(DHPPL) 1차'),
  (6, '코로나 장염 1차'),
  (8, '종합백신(DHPPL) 2차'),
  (8, '코로나 장염 2차'),
  (10, '종합백신(DHPPL) 3차'),
  (10, '켄넬코프 1차'),
  (12, '종합백신(DHPPL) 4차'),
  (12, '켄넬코프 2차'),
  (14, '종합백신(DHPPL) 5차'),
  (14, '인플루엔자 1차'),
  (16, '광견병'),
  (16, '인플루엔자 2차'),
  (18, '항체가 검사'),
];

/// 고양이 표준 일정 — (생후 주령, 라벨).
const _catPlan = <(int, String)>[
  (8, '종합백신(FVRCP) 1차'),
  (11, '종합백신(FVRCP) 2차'),
  (14, '종합백신(FVRCP) 3차'),
  (14, '백혈병 1차'),
  (17, '백혈병 2차'),
  (17, '광견병'),
  (20, '항체가 검사'),
];

/// 생년월일과 종으로 표준 접종 일정 전체를 계산한다(날짜순).
/// [speciesKind] 는 'dog' | 'cat' — null 이거나 그 외 값이면 dog 기준.
List<SuggestedVaccination> standardVaccinationSchedule({
  required DateTime birthDate,
  String? speciesKind,
}) {
  final plan = speciesKind == 'cat' ? _catPlan : _dogPlan;
  final birth = DateTime(birthDate.year, birthDate.month, birthDate.day);
  return [
    for (final (weeks, label) in plan)
      SuggestedVaccination(
        label: label,
        dueDate: birth.add(Duration(days: weeks * 7)),
      ),
  ];
}

/// 오늘(포함) 이후의 제안 일정과, 이미 지나 제외된 건수.
/// 지난 일정은 기본 제외하고 UI 에서 "N건 제외" 한 줄로만 안내한다.
({List<SuggestedVaccination> upcoming, int excluded}) upcomingVaccinationSchedule({
  required DateTime birthDate,
  String? speciesKind,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final base = DateTime(now.year, now.month, now.day);
  final all = standardVaccinationSchedule(
    birthDate: birthDate,
    speciesKind: speciesKind,
  );
  final upcoming = [
    for (final v in all)
      if (!v.dueDate.isBefore(base)) v,
  ];
  return (upcoming: upcoming, excluded: all.length - upcoming.length);
}
