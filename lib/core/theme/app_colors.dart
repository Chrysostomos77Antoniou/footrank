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

  // Ambient background layer. Previously hard-coded inside premium.dart,
  // which meant the app's most pervasive visual surface could not be retuned
  // from the palette.
  static const Color ambientDarkTop = Color(0xFF161D38);
  static const Color ambientDarkMid = Color(0xFF0E1326);
  static const Color ambientDarkBottom = Color(0xFF080B18);
  static const Color ambientLightBottom = Color(0xFFE7EAF1);
  static const Color ambientGlowDark = Color(0xFF2A3461);
  static const Color ambientVignetteDark = Color(0xFF05060E);
  static const Color ambientVignetteLight = Color(0xFFD7DBE6);

  /// Primary text/icon colour on the dark surfaces above.
  static const Color darkOnSurface = Color(0xFFECEEF1);

  /// Primary text/icon colour on the light surfaces above.
  ///
  /// KNOWN ISSUE: pure black leaves light mode with no primary/secondary text
  /// hierarchy once `muted()` derives from it. The redesign spec calls for
  /// ~0xFF0B0F1A instead; deferred because it is a visible change and this
  /// phase is structural. See docs/superpowers/specs/2026-08-16-footrank-redesign-design.md
  static const Color lightOnSurface = Color(0xFF000000);

  /// The single light-mode hairline border value.
  ///
  /// Previously defined twice with different values (0xFFE6E8EC here and
  /// 0xFFE3E6EB inside app_theme.dart); consolidated here so cards, inputs,
  /// dividers and widget-drawn borders can never drift apart again.
  ///
  /// KNOWN ISSUE: at ~1.2:1 against white this fails WCAG 2.2 SC 1.4.11 (3:1)
  /// where it is the *sole* affordance — OutlinedButton and InputDecoration.
  /// Darkening it is a visible change and needs sign-off; tracked in the spec.
  static const Color lightBorder = Color(0xFFE6E8EC);

  /// Dark-mode hairline border: white at low alpha over the navy surfaces.
  static Color get darkBorder => Colors.white.withValues(alpha: 0.08);

  // Hairline borders.
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBorder
          : lightBorder;

  // Muted secondary text/icon color — kept fairly strong so light mode stays
  // legible (low-opacity grey-on-white was washing out). Dark mode sits at
  // 0.72 so secondary text clears WCAG AA (~7:1 on cards) instead of hovering
  // near the 4.5:1 floor like the old 0.6 did.
  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.72 : 0.82);

  static const List<Color> rankColors = [gold, silver, bronze];
}
