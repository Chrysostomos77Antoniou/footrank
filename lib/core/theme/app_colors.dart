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

  /// Accent color (same in both themes, Playtomic-style).
  static Color brand(BuildContext context) => lime;

  /// Readable text/icon color to place on top of the lime accent.
  static const Color onBrand = navy;

  /// Heading/number gradient — navy on light, lime on dark (for contrast).
  static LinearGradient headingGrad(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const LinearGradient(colors: [lime, limeDark])
        : const LinearGradient(colors: [navy, Color(0xFF2C3354)]);
  }

  /// Accent gradient (always lime) for buttons/badges.
  static const LinearGradient brandGrad2 =
      LinearGradient(colors: [lime, limeDark]);

  /// Fixed dark navy background for the auth screen (theme-independent).
  static const LinearGradient authGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C1022), navy, navySoft],
  );

  // Backwards-compatible name used around the app for the accent gradient.
  static LinearGradient brandGrad(BuildContext context) => brandGrad2;

  // Medals
  static const Color gold = Color(0xFFE6B400);
  static const Color silver = Color(0xFF9AA4AD);
  static const Color bronze = Color(0xFFB87333);

  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF3FB950);

  // Surfaces
  static const Color darkBg = Color(0xFF0F1326);
  static const Color darkCard = Color(0xFF1A2038);
  static const Color lightBg = Color(0xFFF3F4F7);
  static const Color lightCard = Colors.white;

  static const List<Color> rankColors = [gold, silver, bronze];
}
