import 'package:flutter/animation.dart';

/// Design tokens — the single source of truth for spacing, radii and motion.
///
/// Use these instead of raw pixel values so the whole app shares one rhythm:
/// spacing follows a 4px scale, radii step consistently, and every animation
/// shares the same durations/curves (which is what makes motion feel cohesive).
class AppSpacing {
  AppSpacing._();

  /// 4 — hairline gaps (icon-to-text nudges).
  static const double xxs = 4;

  /// 8 — tight gaps inside a component.
  static const double xs = 8;

  /// 12 — gap between sibling cards in a list.
  static const double sm = 12;

  /// 16 — default component padding.
  static const double md = 16;

  /// 20 — screen horizontal padding / roomy card padding.
  static const double lg = 20;

  /// 24 — gap between a section's last item and the next section.
  static const double xl = 24;

  /// 32 — major section breaks.
  static const double xxl = 32;

  /// 48 — hero-level separation.
  static const double xxxl = 48;
}

class AppRadius {
  AppRadius._();

  /// 10 — small chips/pills.
  static const double sm = 10;

  /// 12 — inputs and buttons.
  static const double md = 12;

  /// 16 — cards.
  static const double lg = 16;

  /// 20 — hero cards / large surfaces.
  static const double xl = 20;
}

/// Shared motion language: fast feedback, calm entrances, one curve family.
class AppMotion {
  AppMotion._();

  /// 110ms — press feedback (must feel instant).
  static const Duration press = Duration(milliseconds: 110);

  /// 200ms — small state changes (icon swaps, toggles).
  static const Duration quick = Duration(milliseconds: 200);

  /// 320ms — content entrances.
  static const Duration enter = Duration(milliseconds: 320);

  /// Standard easing for anything entering the screen.
  static const Curve easeOut = Curves.easeOutCubic;

  /// Standard easing for anything leaving the screen.
  static const Curve easeIn = Curves.easeInCubic;
}
