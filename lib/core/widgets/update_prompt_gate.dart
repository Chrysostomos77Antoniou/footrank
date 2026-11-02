import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
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
      final config = await (widget.configLoader ??
          UpdatePromptRepository().fetch)();
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

class _UpdateWindow extends StatelessWidget {
  final VoidCallback onUpdate;
  const _UpdateWindow({required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final still = reduceMotion(context);
    return Stack(
      key: const Key('update-prompt'),
      fit: StackFit.expand,
      children: [
        // Swallows every touch, and is not dismissible.
        ModalBarrier(
          dismissible: false,
          color: theme.colorScheme.scrim.withValues(alpha: AppOpacity.scrim),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSemantic.screenPadding),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: still ? Duration.zero : AppMotion.enter,
                curve: AppMotion.easeOut,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Material(
                    color: theme.colorScheme.surface,
                    elevation: AppElevation.flat,
                    borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.system_update_alt_rounded,
                            size: AppIconSize.lg,
                            color: AppColors.brand(context),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Update available',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'A new version of FootRank is ready. '
                            'Please update to keep playing.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.muted(context),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton(
                            onPressed: onUpdate,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                AppSemantic.buttonHeight,
                              ),
                            ),
                            child: const Text('Update now'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
