import 'package:flutter/material.dart';

/// Playtomic-inspired palette: bright lime accent on deep navy.
class AppColors {
  AppColors._();

  // Accent (Playtomic lime)
  static const Color lime = Color(0xFFC7F032);
  static const Color limeDark = Color(0xFFA6CE1E);

  // Brand navy (used as "on accent" text + dark surfaces)
  static const Color navy = Color(0xFF14182B);
  static const Color navySoft = Color(0xFF1B2138);

  /// Deep green used for accents/icons on light surfaces (lime is too pale).
  static const Color limeDeep = Color(0xFF1B7A3D);
  static const Color limeDeeper = Color(0xFF14622F);

  /// Accent color: bright lime in dark mode, deep green in light mode —
  /// so the brand reads clearly on white backgrounds.
  static Color brand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? lime : limeDeep;

  /// Readable text/icon color to place on top of the [brand] accent:
  /// navy on lime (dark mode), white on deep green (light mode).
  static Color onBrand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? navy : Colors.white;

  /// Theme-aware icon/accent color: lime in dark, deep green in light —
  /// so icons stay readable on light backgrounds.
  static Color iconAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? lime : limeDeep;

  /// Heading/number gradient — navy on light, lime on dark (for contrast).
  static LinearGradient headingGrad(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const LinearGradient(colors: [lime, limeDark])
        : const LinearGradient(colors: [navy, Color(0xFF2C3354)]);
  }

  /// Accent gradient for buttons/badges: lime in dark, deep green in light.
  static LinearGradient brandGrad2(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const LinearGradient(colors: [lime, limeDark])
          : const LinearGradient(colors: [limeDeep, limeDeeper]);

  /// Fixed dark navy background for the auth screen (theme-independent).
  static const LinearGradient authGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C1022), navy, navySoft],
  );

  // Backwards-compatible name used around the app for the accent gradient.
  static LinearGradient brandGrad(BuildContext context) => brandGrad2(context);

  // Medals
  static const Color gold = Color(0xFFE6B400);
  static const Color silver = Color(0xFF9AA4AD);
  static const Color bronze = Color(0xFFB87333);

  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF3FB950);

  // Surfaces — dark mode keeps its original navy tone; light mode clean slate.
  static const Color darkBg = Color(0xFF0F1326);
  static const Color darkCard = Color(0xFF1A2038);
  static const Color darkElevated = Color(0xFF222a47);
  static const Color lightBg = Color(0xFFF5F6F8);
  static const Color lightCard = Colors.white;

  // Hairline borders.
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFE6E8EC);

  // Muted secondary text/icon color — kept fairly strong so light mode stays
  // legible (low-opacity grey-on-white was washing out).
  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.6 : 0.82);

  static const List<Color> rankColors = [gold, silver, bronze];
}
