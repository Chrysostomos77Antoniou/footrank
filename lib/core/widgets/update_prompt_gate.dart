import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_tokens.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/update/update_prompt.dart';
import 'package:footrank/core/utils/motion.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef UpdateConfigLoader = Future<UpdatePromptConfig?> Function();
typedef AppVersionLoader = Future<String> Function();
typedef StoreLauncher = Future<bool> Function(Uri uri);

Future<String> _installedVersion() async =>
    (await PackageInfo.fromPlatform()).version;

Future<bool> _openExternally(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// A full-screen layer, placed above the whole app, that shows the "new
/// version" window when -- and only when -- the owner switched it on and this
/// build is older than the newest version.
///
/// It asks the server every time the app opens and every time it comes back
/// from the background, so flipping the switch takes effect on the next open
/// without a release. Anything that goes wrong (offline, no row, a bad
/// setting) shows nothing: the window can never lock people out by accident.
///
/// The window has one button. iPhones go to the App Store, Android phones to
/// Google Play; nothing else closes it.
class UpdatePromptGate extends StatefulWidget {
  final UpdateConfigLoader? configLoader;
  final AppVersionLoader? versionLoader;
  final StoreLauncher? launcher;

  /// Tests only; production reads [defaultTargetPlatform].
  final TargetPlatform? platform;

  const UpdatePromptGate({
    super.key,
    this.configLoader,
    this.versionLoader,
    this.launcher,
    this.platform,
  });

  @override
  State<UpdatePromptGate> createState() => _UpdatePromptGateState();
}

class _UpdatePromptGateState extends State<UpdatePromptGate>
    with WidgetsBindingObserver {
  List<Uri> _targets = const [];
  String _latest = '';
  int _check = 0;

  bool get _blocking => _targets.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final mine = ++_check;
    try {
      final platform = storePlatformFor(
        widget.platform ?? defaultTargetPlatform,
      );
      if (platform == null) return _show(mine, const []);
      final config =
          await (widget.configLoader ?? UpdatePromptRepository().fetch)();
      if (config == null || !config.enabled) return _show(mine, const []);
      final installed = await (widget.versionLoader ?? _installedVersion)();
      if (!isOlderVersion(installed, config.latestVersion)) {
        return _show(mine, const []);
      }
      _latest = config.latestVersion;
      _show(mine, storeUrisFor(config, platform));
    } catch (_) {
      // Could not find out: leave things as they are.
    }
  }

  void _show(int check, List<Uri> targets) {
    if (!mounted || check != _check) return;
    if (listEquals(targets, _targets)) return;
    setState(() => _targets = targets);
  }

  Future<void> _update() async {
    final launch = widget.launcher ?? _openExternally;
    for (final uri in _targets) {
      if (await launch(uri)) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_blocking) return const SizedBox.shrink();
    return _UpdateWindow(onUpdate: _update, version: _latest);
  }
}

// Full-bleed, dark and quiet, the way an Apple launch screen is: one icon, one
// sentence, one button. Everything arrives in a short staggered sequence
// (strong ease-out, each piece under 300ms) and the button answers the finger
// at once with a 3% press-in. With reduced motion, everything is simply there.
const Curve _strongOut = Cubic(0.23, 1, 0.32, 1);
const Color _ink = Color(0xFF070A0E);

class _UpdateWindow extends StatefulWidget {
  final VoidCallback onUpdate;
  final String version;
  const _UpdateWindow({required this.onUpdate, required this.version});

  @override
  State<_UpdateWindow> createState() => _UpdateWindowState();
}

class _UpdateWindowState extends State<_UpdateWindow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// A piece of the sequence: fades in and rises 18px between [a] and [b].
  Widget _step(double a, double b, Widget child, {double rise = 18}) {
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(a, b, curve: _strongOut),
    );
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (context, child) => Opacity(
        opacity: curve.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, rise * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        key: const Key('update-prompt'),
        fit: StackFit.expand,
        children: [
          // The scene fills the whole screen, edge to edge.
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _c,
              curve: const Interval(0, 0.4, curve: _strongOut),
            ),
            child: const _Scene(),
          ),
          // Swallows every touch, and is not dismissible.
          const ModalBarrier(dismissible: false, color: Colors.transparent),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Spacer(flex: 3),
                          _step(0.04, 0.4, const _HeroIcon(), rise: 10),
                          const SizedBox(height: 36),
                          if (widget.version.isNotEmpty)
                            _step(
                              0.16,
                              0.5,
                              _VersionTag(version: widget.version),
                            ),
                          if (widget.version.isNotEmpty)
                            const SizedBox(height: 16),
                          _step(
                            0.22,
                            0.58,
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'A better',
                                textAlign: TextAlign.center,
                                style: _headline,
                              ),
                            ),
                            rise: 24,
                          ),
                          _step(
                            0.30,
                            0.66,
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'FootRank.',
                                textAlign: TextAlign.center,
                                style: _headline.copyWith(
                                  color: AppColors.lime,
                                ),
                              ),
                            ),
                            rise: 24,
                          ),
                          const SizedBox(height: 18),
                          _step(
                            0.42,
                            0.76,
                            const Text(
                              'A new version is ready.\n'
                              'Update to keep playing.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF9BA7B3),
                              ),
                            ),
                          ),
                          const Spacer(flex: 4),
                          _step(
                            0.55,
                            0.92,
                            _UpdateButton(onPressed: widget.onUpdate),
                            rise: 22,
                          ),
                          const SizedBox(height: 14),
                          _step(
                            0.66,
                            1,
                            const Text(
                              'Your teams and matches stay safe.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF6D7A87),
                              ),
                            ),
                            rise: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const TextStyle _headline = TextStyle(
  fontFamily: AppFonts.display,
  fontSize: 42,
  height: 1.08,
  fontWeight: FontWeight.w800,
  letterSpacing: -1.6,
  color: Colors.white,
);

/// The app icon, lit from below by a green glow, inside a hairline ring.
class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: AppColors.lime.withValues(alpha: 0.28),
            blurRadius: 60,
            spreadRadius: 2,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Image.asset(
          'assets/branding/app_icon_512.png',
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// "VERSION 1.1.9" -- a hairline capsule, small capitals, one accent dot.
class _VersionTag extends StatelessWidget {
  final String version;
  const _VersionTag({required this.version});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.lime,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'VERSION  $version',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: Color(0xFFD5DCE3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill that sinks to 97% under the finger, like any iOS control.
class _UpdateButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _UpdateButton({required this.onPressed});

  @override
  State<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<_UpdateButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return Semantics(
      button: true,
      label: 'Update now',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down && !still ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: _strongOut,
          child: AnimatedOpacity(
            opacity: _down ? 0.88 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              height: 58,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.lime,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.lime.withValues(alpha: 0.30),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Text(
                'Update now',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The backdrop: near-black with a green aurora rising from the bottom, a
/// soft halo behind the icon and faint sonar rings, so the screen has depth
/// without a single hard edge.
class _Scene extends StatelessWidget {
  const _Scene();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(child: CustomPaint(painter: _ScenePainter()));
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_ink, Color(0xFF0A1410), Color(0xFF0C2A1B)],
          stops: [0, 0.55, 1],
        ).createShader(Offset.zero & size),
    );

    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(
      Offset(w / 2, h * 1.02),
      w * 1.15,
      AppColors.heroDarkA.withValues(alpha: 0.85),
    );
    glow(
      Offset(w / 2, h * 0.272),
      w * 0.75,
      AppColors.limeDeep.withValues(alpha: 0.55),
    );
    glow(
      Offset(w / 2, h * 0.272),
      w * 0.32,
      AppColors.lime.withValues(alpha: 0.10),
    );

    // Sonar rings around the icon.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final c = Offset(w / 2, h * 0.272);
    for (var i = 0; i < 4; i++) {
      ring.color = Colors.white.withValues(alpha: 0.075 - i * 0.015);
      canvas.drawCircle(c, 92 + i * 62.0, ring);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
