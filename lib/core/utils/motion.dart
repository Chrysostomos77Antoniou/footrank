import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// Whether this user has asked the system to reduce motion.
///
/// Checks BOTH sources, which is the whole point of this helper existing:
///
/// * `MediaQuery.disableAnimationsOf` reflects Android's "Remove animations"
///   developer/accessibility setting.
/// * `accessibilityFeatures.reduceMotion` reflects iOS's Settings →
///   Accessibility → Motion → Reduce Motion.
///
/// The two existing checks in this codebase used only the first, so iOS users
/// with Reduce Motion enabled were served the full animation set regardless.
bool reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
        .reduceMotion;

/// Whether decorative video (the auth background, the splash intro) should
/// play.
///
/// NOTE: Flutter 3.32.6's `AccessibilityFeatures` exposes accessibleNavigation,
/// invertColors, disableAnimations, boldText, reduceMotion, highContrast and
/// onOffSwitchLabels — there is no `autoPlayVideos` flag to read, so this falls
/// back to the reduced-motion preference. A user asking for less motion is not
/// asking for a looping background video.
bool decorativeVideoAllowed(BuildContext context) => !reduceMotion(context);

/// Crossfades between loading, error, empty and content instead of hard-cutting.
///
/// Every async screen in this app returned a skeleton and then swapped it for
/// real content in a single frame, so the shimmer built specifically to make
/// loading feel premium vanished instantly. [FutureBuilder] rebuilds do not
/// animate on their own — [AnimatedSwitcher] needs a differing key or
/// runtimeType to fire, which is what [switcherKey] is for.
///
/// Motion choice: a pure opacity crossfade on [Curves.linear]. `AnimatedSwitcher`
/// defaults both of its curves to linear already, but relying on that default
/// is how the wrong curve silently appears later — so both are explicit here.
/// Easing an opacity-only change adds nothing and reads as sluggish.
///
/// The outgoing child leaves faster than the incoming arrives (150ms vs 300ms)
/// so the two never sit at 50% opacity fighting each other.
class AsyncSwitcher extends StatelessWidget {
  final Widget child;

  /// Distinguishes states from one another. Supply a stable value per state
  /// (e.g. 'loading' / 'error' / 'content') when consecutive states would
  /// otherwise share a runtimeType.
  final Object? switcherKey;

  final Duration duration;
  final Duration reverseDuration;

  const AsyncSwitcher({
    super.key,
    required this.child,
    this.switcherKey,
    this.duration = AppMotion.enter,
    this.reverseDuration = AppMotion.quick,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      // Default layoutBuilder stacks children centred, which collapses a
      // full-height list into its intrinsic size mid-transition. Aligning to
      // the top-left and sizing to the incoming child keeps lists still.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(switcherKey ?? child.runtimeType),
        child: child,
      ),
    );
  }
}
