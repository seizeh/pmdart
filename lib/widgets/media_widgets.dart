import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../motion/motion.dart';
import '../theme/app_palette.dart';

/// 첨부 영상 공용 위젯 — 포스터 타일([VideoPosterTile])과 전체화면 플레이어
/// ([VideoPlayerScreen]). 게시글(자유·소식)·시설 후기·채팅이 함께 쓴다.

/// 포스터 없는 영상의 폴백 배경(어두운 타일).
const Color _kVideoFallbackBg = Color(0xFF2B2B2B);

/// 전체화면 플레이어 열기 — 채팅 이미지 뷰어와 동일한 페이드 전환(검정 배리어).
void openVideoPlayer(BuildContext context, String url) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => VideoPlayerScreen(url: url),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// 영상 포스터 타일 — 포스터 이미지 + 중앙 ▶ 오버레이. 포스터가 없거나 로드에
/// 실패하면 어두운 배경 + ▶ 로 폴백. [handleTap] 이면 탭 시 전체화면 플레이어를
/// 연다(바깥에서 탭을 처리하는 경우 false 로 시각만 사용).
class VideoPosterTile extends StatelessWidget {
  final String videoUrl;
  final String? posterUrl;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final double badgeSize;

  /// 포스터 디코딩 폭 힌트(카드/타일 크기에 맞춰 저해상 디코딩).
  final int? cacheWidth;

  /// 탭 시 이 위젯이 직접 플레이어를 열지 여부.
  final bool handleTap;

  const VideoPosterTile({
    super.key,
    required this.videoUrl,
    this.posterUrl,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.badgeSize = 48,
    this.cacheWidth,
    this.handleTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget body = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (posterUrl != null)
            Image.network(
              posterUrl!,
              fit: fit,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: _kVideoFallbackBg),
            )
          else
            const ColoredBox(color: _kVideoFallbackBg),
          Center(child: VideoPlayBadge(size: badgeSize)),
        ],
      ),
    );
    if (!handleTap) return body;
    return Pressable(
      borderRadius: borderRadius,
      onTap: () => openVideoPlayer(context, videoUrl),
      child: body,
    );
  }
}

/// 중앙 ▶ 배지 — 포스터·썸네일 위에서 영상임을 알리는 공용 오버레이.
class VideoPlayBadge extends StatelessWidget {
  final double size;
  const VideoPlayBadge({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0x8A000000),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size: size * 0.62,
        color: Colors.white,
      ),
    );
  }
}

/// 전체화면 영상 플레이어 — 네트워크 재생, 재생/일시정지·진행바·닫기.
/// 화면 탭으로 컨트롤을 토글하고, 배경 검정(채팅 이미지 뷰어와 동일 문법).
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  const VideoPlayerScreen({super.key, required this.url});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _error = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _controller.play();
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = true);
        });
    // 재생/일시정지·종료 등 상태 변화에 맞춰 컨트롤 아이콘 갱신.
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      // 끝까지 본 뒤 ▶ 누르면 처음부터 다시.
      if (_controller.value.position >= _controller.value.duration) {
        _controller.seekTo(Duration.zero);
      }
      _controller.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Center(
              child: _error
                  ? const _PlayerError()
                  : !v.isInitialized
                  ? const CircularProgressIndicator(color: Colors.white)
                  : AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
            ),
            if (_showControls) ...[
              // 재생/일시정지 — 중앙.
              if (!_error && v.isInitialized)
                Center(
                  child: Pressable(
                    borderRadius: BorderRadius.circular(100),
                    onTap: _togglePlay,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0x8A000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        v.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // 닫기 — 우상단.
              Positioned(
                top: 0,
                right: 8,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              // 진행바 + 시간 — 하단.
              if (!_error && v.isInitialized)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: context.colors.primary,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmt(v.position),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                _fmt(v.duration),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: Colors.white70, size: 36),
        SizedBox(height: 10),
        Text(
          '영상을 재생할 수 없어요',
          style: TextStyle(fontSize: 14, color: Colors.white70),
        ),
      ],
    );
  }
}
