import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_tokens.dart';
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
    return _UpdateWindow(onUpdate: _update);
  }
}

// Apple-style sheet in light blue and white. Motion follows one rule: things
// arrive fast and settle softly (strong ease-out, under 300ms), and the button
// answers the finger at once (a 3% press-in).
const Color _skyTop = Color(0xFFE3F1FF);
const Color _skyBottom = Color(0xFFFFFFFF);
const Color _skyAccent = Color(0xFF1B7BE6);
const Color _skyAccentLight = Color(0xFF5AB0FF);
const Color _skyInk = Color(0xFF0B1B2E);
const Color _skyMuted = Color(0xFF5B6B7F);
const Curve _strongOut = Cubic(0.23, 1, 0.32, 1);

class _UpdateWindow extends StatelessWidget {
  final VoidCallback onUpdate;
  const _UpdateWindow({required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final enter = still ? Duration.zero : const Duration(milliseconds: 260);
    return Stack(
      key: const Key('update-prompt'),
      fit: StackFit.expand,
      children: [
        // Swallows every touch, and is not dismissible. The app behind
        // frosts over like an iOS sheet.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: enter,
          curve: _strongOut,
          builder: (context, t, child) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
            child: ModalBarrier(
              dismissible: false,
              color: _skyInk.withValues(alpha: 0.38 * t),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSemantic.screenPadding),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: enter,
                curve: _strongOut,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - t)),
                    child: Transform.scale(
                      scale: 0.95 + 0.05 * t,
                      child: child,
                    ),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: _sheet(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sheet(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_skyTop, _skyBottom],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: _skyAccent.withValues(alpha: 0.22),
            blurRadius: 48,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: _skyInk.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_skyAccentLight, _skyAccent],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: _skyAccent.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_downward_rounded,
                    size: 38,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Update available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: _skyInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A new version of FootRank is ready. '
                'Please update to keep playing.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4, color: _skyMuted),
              ),
              const SizedBox(height: 26),
              _UpdateButton(onPressed: onUpdate),
            ],
          ),
        ),
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
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3A92F0), _skyAccent],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _skyAccent.withValues(alpha: 0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Text(
              'Update now',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
