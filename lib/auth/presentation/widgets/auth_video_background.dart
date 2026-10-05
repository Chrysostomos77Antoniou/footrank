import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/utils/motion.dart';

/// Full-screen looping, muted video background for the auth screens, with a
/// neutral dark gradient scrim (identical in light and dark themes) so
/// foreground text and the frosted card stay readable.
/// Falls back to the flat dark gradient until the video is ready, if it fails
/// to load, or when the user asks for reduced motion.
class AuthVideoBackground extends StatefulWidget {
  final Widget child;
  const AuthVideoBackground({super.key, required this.child});

  @override
  State<AuthVideoBackground> createState() => _AuthVideoBackgroundState();
}

class _AuthVideoBackgroundState extends State<AuthVideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Decorative video is skipped under reduced motion.
    if (decorativeVideoAllowed(context)) _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.asset('assets/video/auth_bg.mp4');
      await c.initialize();
      c
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _ready = true;
      });
    } catch (_) {
      // Leave fallback gradient in place if the video can't load.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base gradient (also the fallback)
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.authGradient),
        ),
        // Video, cover-cropped to fill the screen
        if (_ready && _controller != null)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        // Neutral scrim: lighter at the top so the video reads, heavier at
        // the bottom where the form card sits.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.darkBg.withValues(alpha: 0.42),
                AppColors.darkBg.withValues(alpha: 0.50),
                AppColors.darkBg.withValues(alpha: 0.82),
              ],
              stops: const [0, 0.35, 1],
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
