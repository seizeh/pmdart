import 'package:flutter/foundation.dart';

/// 첨부 진행률 고리에 넣을 값 — 압축과 업로드를 **한 줄로** 잇는다.
///
/// `ValueNotifier` 인 이유는 성능이다. 진행 콜백은 초당 수십 번 오는데 화면에서
/// `setState` 를 돌면 편집 히어로 전체(Image.network·점진 블러 패널·입력들)가
/// 그때마다 다시 그려진다. 고리만 듣게 해서 리빌드를 버튼 하나로 가둔다.
///
/// 값의 뜻:
///   · `null` — 진행 중 아님(또는 진행률을 알 수 없음 → 무한 회전으로 폴백)
///   · 0.0~1.0 — 전체 기준 진행률. **되돌아가지 않는다.**
class AttachmentProgress extends ValueNotifier<double?> {
  AttachmentProgress() : super(null);

  /// 영상 재인코딩이 전체에서 차지하는 몫.
  ///
  /// 압축과 업로드는 서로 다른 일이라 "정확한" 비율이란 게 없다. 고리가 뒤로
  /// 가지 않도록 구간을 나눠 둔 값이고, 실측한 뒤 조정하면 된다. 압축이 끝나면
  /// 올릴 바이트가 줄어 있으므로 뒷구간이 그만큼 빨리 찬다.
  static const double compressShare = 0.35;

  bool _compressed = false;

  /// 첨부 시작 — 아직 진행률을 모르는 상태(무한 회전)로 둔다. picker 가 떠 있는
  /// 동안이 여기다.
  void begin() {
    _compressed = false;
    value = null;
  }

  /// 재인코딩 진행. 이 메서드가 한 번이라도 불리면 업로드 구간은 [compressShare]
  /// 뒤에서 시작한다.
  void compressing(double fraction) {
    _compressed = true;
    value = (fraction.clamp(0.0, 1.0)) * compressShare;
  }

  /// 전송 진행. 압축이 없었으면 0부터, 있었으면 [compressShare] 부터 채운다.
  void uploading(double fraction) {
    final base = _compressed ? compressShare : 0.0;
    value = base + (fraction.clamp(0.0, 1.0)) * (1 - base);
  }

  /// 끝(성공·실패 무관) — 고리를 지운다.
  void done() {
    _compressed = false;
    value = null;
  }
}
