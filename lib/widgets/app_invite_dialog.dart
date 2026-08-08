import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../env.dart';
import '../theme/app_palette.dart';
import '../utils/labels.dart';

/// 웹에서 **앱 전용 기능**(지도·채팅 등)을 누르면 띄우는 설치 안내.
///
/// 웹은 앱 유입 퍼널이므로(docs/web-port.md) 이런 기능은 메뉴에서 숨기지 않고
/// **보여준 뒤 앱으로 유도**한다 — 무엇을 더 할 수 있는지 알려야 설치로 이어진다.
///
/// 시각 언어는 [AuthWallDialog] 와 동일하다(같은 라운드·같은 버튼 구성).
/// 스토어 주소([Env.storeUrlIos]/[Env.storeUrlAndroid])가 비어 있으면 — 출시 전
/// 기본값 — 설치 버튼 대신 "출시 준비 중" 안내만 보여준다(죽은 링크 방지).
class AppInviteDialog extends StatelessWidget {
  const AppInviteDialog({super.key, required this.feature});

  /// 무엇을 하려다 막혔는지(예: '지도', '채팅'). 문구에 그대로 들어간다.
  final String feature;

  static Future<void> show(BuildContext context, {required String feature}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => AppInviteDialog(feature: feature),
    );
  }

  /// 방문자가 안드로이드인가 — 웹에서 `defaultTargetPlatform` 은 브라우저의 OS 를
  /// 알려 준다. 플랫폼별로 **갈 곳이 하나뿐**이어야 한다: 안드로이드 사용자에게
  /// App Store 버튼을 보여 주는 건 막다른 길이다(iOS 만 출시된 지금 실제로 그랬다).
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 이 방문자가 지금 갈 수 있는 스토어 주소(없으면 빈 문자열).
  static String get _storeUrl =>
      _isAndroid ? Env.storeUrlAndroid : Env.storeUrlIos;

  /// Play 출시 전 안드로이드 방문자에게만 보여줄 테스터 신청 폼.
  /// 스토어가 열리면(=storeUrlAndroid 설정) 자동으로 사라진다.
  static String get _testerUrl =>
      _isAndroid && Env.storeUrlAndroid.isEmpty ? Env.testerFormUrl : '';

  static bool get _hasStore => _storeUrl.isNotEmpty;

  Future<void> _open(BuildContext context, String url) async {
    Navigator.pop(context);
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      /* 팝업 차단 등 — 무해하게 무시 */
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.phone_iphone_rounded,
                size: 32,
                color: c.primaryDark,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${withTopicParticle(feature)} 앱에서 이용할 수 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _hasStore
                  ? '앱에서는 동네 지도와 이웃과의 채팅까지 모두 쓸 수 있어요.'
                  : _testerUrl.isNotEmpty
                  ? '안드로이드는 지금 비공개 테스트 중이에요.\n'
                        '테스터로 참여하시면 먼저 써보실 수 있어요.'
                  : '앱 출시를 준비하고 있어요. 곧 스토어에서 만나요!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            if (_hasStore)
              _button(
                context,
                _isAndroid ? 'Google Play 에서 받기' : 'App Store 에서 받기',
                () => _open(context, _storeUrl),
                primary: true,
              )
            else if (_testerUrl.isNotEmpty)
              _button(
                context,
                '안드로이드 테스터 신청하기',
                () => _open(context, _testerUrl),
                primary: true,
              ),
            if (_hasStore || _testerUrl.isNotEmpty) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: c.textSecondary,
                ),
                child: Text(
                  _hasStore || _testerUrl.isNotEmpty ? '나중에 할래요' : '닫기',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    required bool primary,
  }) {
    // 테마 버튼은 minimumSize 가 Size.fromHeight(폭 무한)라 폭을 로컬에서 정한다.
    final child = Text(label);
    return SizedBox(
      width: double.infinity,
      child: primary
          ? ElevatedButton(onPressed: onTap, child: child)
          : OutlinedButton(onPressed: onTap, child: child),
    );
  }
}
