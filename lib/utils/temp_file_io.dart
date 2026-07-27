import 'dart:io';

/// 촬영·선택 후 남은 임시 파일 삭제(잔존 방지). 실패는 무해하므로 삼킨다.
Future<void> deleteTempFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // 이미 삭제됐거나 권한 없음 — OS 가 임시 디렉터리를 정리한다.
  }
}
