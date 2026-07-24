import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:footrank/core/theme/app_colors.dart';

/// Branded video splash shown over the app while it boots (auth/theme/
/// Supabase/Firebase init), replacing the old static splash image. Plays
/// once, full-bleed, then fades away to reveal the app underneath (which by
/// then has already resolved its first route -- login, for a logged-out
/// user). Tap anywhere to skip; respects the system's reduced-motion setting.
class VideoSplashOverlay extends StatefulWidget {
  final VoidCallback onFinished;
  const VideoSplashOverlay({super.key, required this.onFinished});

  @override
  State<VideoSplashOverlay> createState() => _VideoSplashOverlayState();
}

class _VideoSplashOverlayState extends State<VideoSplashOverlay>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  bool _dismissing = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.asset(
        'assets/video/splash_intro.mp4',
      );
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.setLooping(false);
      c.setVolume(0);
      c.addListener(_onTick);
      setState(() => _controller = c);

      // Reduced motion: skip straight to the app instead of playing.
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _dismiss();
        return;
      }
      _started = true;
      await c.play();
    } catch (_) {
      // Video failed to load (e.g. asset missing on this build) -- don't
      // strand the user on a blank overlay.
      _dismiss();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !_started || _dismissing) return;
    final value = c.value;
    if (value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 80)) {
      _dismiss();
    }
  }

  void _dismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _controller?.pause();
    _out.forward().whenComplete(() {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnimatedBuilder(
      animation: _out,
      builder: (context, child) {
        final t = Curves.easeInCubic.transform(_out.value);
        return IgnorePointer(
          ignoring: _dismissing,
          child: Opacity(opacity: 1 - t, child: child),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox.expand(
            // Explicit full-screen size for this whole layer -- the brand
            // gradient is always present and always covers edge-to-edge, so
            // the app underneath is never visible, before or during the
            // video (which is layered on top only once ready).
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.authGradient),
                ),
                if (controller != null && controller.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
