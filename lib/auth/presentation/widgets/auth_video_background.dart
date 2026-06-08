import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// Full-screen looping, muted video background for the auth screens, with a
/// dark gradient overlay so foreground text/inputs stay readable.
/// Falls back to the brand navy gradient until the video is ready (or if it
/// fails to load).
class AuthVideoBackground extends StatefulWidget {
  final Widget child;
  const AuthVideoBackground({super.key, required this.child});

  @override
  State<AuthVideoBackground> createState() => _AuthVideoBackgroundState();
}

class _AuthVideoBackgroundState extends State<AuthVideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
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
        // Base brand gradient (also the fallback)
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
        // Dark overlay for contrast/readability
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.70),
                Colors.black.withValues(alpha: 0.82),
              ],
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
