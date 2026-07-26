/// 웹에는 파일 시스템이 없다 — XFile 은 blob URL 이라 GC 대상이다.
Future<void> deleteTempFile(String path) async {}
