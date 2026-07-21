/// (구) 화면 개발용 목 데이터 파일 — 실데이터 전환이 끝나 내용은 모두 제거됐다.
/// 라이브 심볼은 이동: 펫 모델 → `models/pet.dart`, 라벨/시간 유틸 → `utils/labels.dart`.
///
/// 진행 중 작업(post_create_screen WIP)이 이 경로로 `categoryLabel` 을 import
/// 하고 있어 재수출 심(shim)으로만 남겨 둔다 — 해당 작업 정리 시 함께 삭제할 것.
library;

export '../utils/labels.dart' show categoryLabel;
