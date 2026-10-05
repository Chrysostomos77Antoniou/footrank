import 'package:flutter/material.dart';

/// FootRank palette.
///
/// Two themes that follow the system setting:
///  * **Pitch Night** (dark): neutral graphite surfaces. Green appears only on
///    the rank hero card; lime marks actions, the active nav state and the key
///    numbers.
///  * **Matchday** (light): soft green-tinted white, deep green accents, lime
///    still the fill of the primary action.
class AppColors {
  AppColors._();

  // Accent
  static const Color lime = Color(0xFFC8F031);
  static const Color limeDark = Color(0xFFA6CE1E);

  /// Text/icon colour placed on lime in dark mode (Pitch Night ink).
  static const Color navy = Color(0xFF0C1015);
  static const Color navySoft = Color(0xFF151B22);

  /// Matchday ink: text on lime, and primary text in light mode.
  static const Color ink = Color(0xFF0E1A14);

  /// Deep greens: accent for text/icons on light surfaces, hero card fill.
  static const Color limeDeep = Color(0xFF14663A);
  static const Color limeDeeper = Color(0xFF0D4A2A);

  /// Rank hero card gradient endpoints (dark mode only uses these greens).
  static const Color heroDarkA = Color(0xFF17613A);
  static const Color heroDarkB = Color(0xFF0C3A24);

  /// Accent for text/icons: lime in dark, deep green in light (lime is too
  /// faint on white).
  static Color brand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? lime : limeDeep;

  /// Readable colour on top of [brand] used as a fill.
  static Color onBrand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? navy : Colors.white;

  /// Theme-aware icon/accent colour.
  static Color iconAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? lime : limeDeep;

  /// Fill of the primary action: lime in BOTH themes.
  static const Color action = lime;

  /// Text/icon on [action]: ink in both themes.
  static Color onAction(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? navy : ink;

  /// Heading/number gradient.
  static LinearGradient headingGrad(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const LinearGradient(colors: [lime, limeDark])
        : const LinearGradient(colors: [ink, Color(0xFF2C3D33)]);
  }

  /// Accent gradient for badges.
  static LinearGradient brandGrad2(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const LinearGradient(colors: [lime, limeDark])
          : const LinearGradient(colors: [limeDeep, limeDeeper]);

  /// The rank hero card: green in both themes (the one green surface in dark).
  static LinearGradient heroGrad(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [heroDarkA, heroDarkB])
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [limeDeep, limeDeeper]);

  /// Fixed dark scrim colour used over the auth video (both themes).
  static const LinearGradient authGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0C1015), Color(0xFF0C1015), Color(0xFF151B22)],
  );

  static LinearGradient brandGrad(BuildContext context) => brandGrad2(context);

  // Medals
  static const Color gold = Color(0xFFE6B400);
  static const Color silver = Color(0xFF9AA4AD);
  static const Color bronze = Color(0xFFB87333);

  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF3FB950);

  /// Danger as text/icon: soft red on dark, deep red on light.
  static Color dangerText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFF8A8A)
          : const Color(0xFFB3261E);

  // Surfaces
  static const Color darkBg = Color(0xFF0C1015);
  static const Color darkCard = Color(0xFF151B22);
  static const Color darkElevated = Color(0xFF1D252E);
  static const Color darkChip = Color(0xFF1F2831);
  static const Color darkNav = Color(0xFF10151B);
  static const Color lightBg = Color(0xFFF2F5F3);
  static const Color lightCard = Colors.white;
  static const Color lightChip = Color(0xFFEAF7B8);

  // Ambient layer is now flat; these remain so older call sites compile.
  static const Color ambientDarkTop = darkBg;
  static const Color ambientDarkMid = darkBg;
  static const Color ambientDarkBottom = darkBg;
  static const Color ambientLightBottom = lightBg;
  static const Color ambientGlowDark = darkBg;
  static const Color ambientVignetteDark = darkBg;
  static const Color ambientVignetteLight = lightBg;

  /// Primary text on dark surfaces.
  static const Color darkOnSurface = Color(0xFFF1F4F7);

  /// Primary text on light surfaces.
  static const Color lightOnSurface = ink;

  /// Secondary text.
  static const Color darkSecondary = Color(0xFFAAB5C0);
  static const Color lightSecondary = Color(0xFF55665C);

  /// Hairline borders: white .07 on dark, ink .07 on light.
  static const Color lightBorder = Color(0x120E1A14);
  static Color get darkBorder => Colors.white.withValues(alpha: 0.07);

  /// Input outline (stronger than a card hairline so the field reads).
  static Color inputBorder(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : ink.withValues(alpha: 0.16);

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBorder
          : lightBorder;

  /// Raised surface inside a card (chips, icon wells).
  static Color chip(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkChip : lightChip;

  /// Icon colour on a [chip] well.
  static Color onChip(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFAEB9C4)
          : limeDeep;

  /// Secondary text/icon colour.
  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSecondary
          : lightSecondary;

  static const List<Color> rankColors = [gold, silver, bronze];
}
