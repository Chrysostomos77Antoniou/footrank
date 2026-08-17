import 'package:flutter/animation.dart';

/// Design tokens — the single source of truth for spacing, radii and motion.
///
/// Use these instead of raw pixel values so the whole app shares one rhythm:
/// spacing follows a 4px scale, radii step consistently, and every animation
/// shares the same durations/curves (which is what makes motion feel cohesive).
///
/// The file is organised in the three tiers Material 3 uses:
///
///   Tier 1 — reference: raw primitives ([AppSpacing], [AppRadius]).
///   Tier 2 — semantic:  what a value *means* ([AppSemantic], [AppElevation],
///                       [AppOpacity], [AppIconSize], [AppFonts],
///                       [AppTypeScale]).
///   Tier 3 — component: `app_theme.dart`, which must consume tier 2 only.
///
/// The rule that makes this work: **widgets reach for tier 2, never tier 1.**
/// `AppSemantic.cardRadius` survives a decision to make cards rounder;
/// `AppRadius.lg` does not, because it cannot tell you which of its callers
/// meant "card" and which merely wanted 16.
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

  /// How far an incoming page drifts up, as a fraction of its height.
  /// Small on purpose: less travel reads as more expensive.
  static const double pageSlideOffset = 0.02;
}

/// Tier 2 — semantic tokens. What a value *means*, not what it is.
///
/// Every widget should reach for these rather than [AppSpacing]/[AppRadius]
/// directly, so a change of mind about (say) card roundness happens in one
/// place instead of in every file that happened to type 16.
class AppSemantic {
  AppSemantic._();

  // ---- Radii -------------------------------------------------------------

  /// Cards and other large surfaces.
  static const double cardRadius = AppRadius.lg;

  /// Buttons, inputs, and anything the user manipulates directly.
  static const double controlRadius = AppRadius.md;

  /// Chips and small status pills.
  static const double chipRadius = AppRadius.xl;

  /// Transient overlays that sit above content (snackbars, tooltips).
  ///
  /// OFF-SCALE (14 sits between [AppRadius.md] 12 and [AppRadius.lg] 16).
  /// Preserved at its shipped value so this phase stays visually neutral;
  /// flagged for snapping to 16 when the screens are reworked.
  static const double overlayRadius = 14;

  /// Fully rounded. Use for avatars and true pill shapes, never as a
  /// stand-in for [chipRadius].
  static const double pill = 999;

  // ---- Spacing -----------------------------------------------------------

  /// Horizontal padding at the edge of a screen.
  static const double screenPadding = AppSpacing.lg;

  /// Vertical gap between two distinct sections of a screen.
  static const double sectionGap = AppSpacing.xl;

  /// Vertical gap between sibling rows/cards in a list.
  static const double rowGap = AppSpacing.sm;

  /// Padding inside a card.
  static const double cardPadding = AppSpacing.md;

  /// Gap between an icon and the text it labels.
  static const double iconGap = AppSpacing.xs;

  // ---- Sizes -------------------------------------------------------------

  /// 48 — minimum interactive target on every side.
  ///
  /// Flutter's own accessibility checklist specifies 48x48; WCAG 2.2 SC 2.5.8
  /// sets a lower floor of 24x24, so 48 satisfies both. Raised from the
  /// previous 44 during the design-system redesign.
  static const double minTapTarget = 48;

  /// Full-width primary button height.
  static const double buttonHeight = 52;

  /// Bottom navigation bar height.
  static const double navBarHeight = 70;

  /// Hairline border on cards, inputs and dividers.
  static const double borderWidth = 1;

  /// Border on a focused input — thicker so focus is never colour-only.
  static const double focusedBorderWidth = 1.5;
}

/// Elevation strategy.
///
/// FootRank deliberately opts out of Material 3 tonal elevation: surfaces are
/// distinguished by a hairline border rather than a surface-tint overlay or a
/// shadow. This is an *outlined* aesthetic and it is a deliberate decision, so
/// it lives here as a named token instead of being re-litigated by every new
/// widget with a stray `surfaceTintColor: Colors.transparent`.
class AppElevation {
  AppElevation._();

  /// The app's default: no shadow, no tonal tint, border-defined surfaces.
  static const double flat = 0;
}

/// Opacity values that carry meaning. Named so a reader can tell an
/// intentional 0.72 from a number somebody guessed.
class AppOpacity {
  AppOpacity._();

  /// Secondary text/icons in dark mode. Clears WCAG AA (~7:1 on cards).
  static const double mutedDark = 0.72;

  /// Secondary text/icons in light mode.
  static const double mutedLight = 0.82;

  /// Hairline border in dark mode (white at this alpha).
  static const double borderDark = 0.08;

  /// Selected navigation destination indicator fill.
  static const double navIndicator = 0.18;

  /// Unselected navigation label/icon. Applied in both brightnesses, unlike
  /// `AppColors.muted()` which splits — preserved as-is here so this phase
  /// changes no pixels.
  static const double navUnselected = 0.72;

  /// A page being covered by an incoming route recedes to this opacity.
  static const double coveredPage = 0.88;
}

/// Icon sizes. Three steps only — a fourth would be a design decision, not a
/// convenience.
class AppIconSize {
  AppIconSize._();

  /// 18 — inline with body text.
  static const double sm = 18;

  /// 24 — default, and the size every tappable icon assumes.
  static const double md = 24;

  /// 32 — feature/empty-state icons.
  static const double lg = 32;
}

/// Font families. Two, never three (NN/g: 1–2 families maximum).
class AppFonts {
  AppFonts._();

  /// Sora — expressive headings and numbers.
  static const String display = 'Sora';

  /// Manrope — everything meant to be read.
  static const String body = 'Manrope';
}

/// FootRank's type scale.
///
/// **Documented deviation:** this is intentionally compressed against the
/// Material 3 spec (M3 `displayLarge` is 57; ours is 34) because FootRank is a
/// dense sports app where a 57px heading would push the actual content below
/// the fold. It is the app's own scale and is stated as such rather than
/// implicitly presented as M3.
///
/// Body text keeps a 1.4–1.6x line-height multiplier per NN/g guidance;
/// headings tighten to 1.1 because large type needs proportionally less
/// leading.
class AppTypeScale {
  AppTypeScale._();

  // Display — Sora, tight leading.
  static const double display1 = 34;
  static const double display2 = 28;
  static const double display3 = 24;

  // Headline — Sora.
  static const double headline1 = 22;
  static const double headline2 = 20;

  // Title.
  static const double title1 = 18;
  static const double title2 = 16;
  static const double title3 = 14;

  // Body — Manrope.
  static const double body1 = 16;
  static const double body2 = 14;
  static const double body3 = 12;

  // Label.
  static const double label1 = 14;
  static const double label2 = 12;
  static const double label3 = 11;

  /// Button text.
  ///
  /// OFF-SCALE (15 sits between [body2] 14 and [body1] 16). Deliberate — it
  /// keeps button labels from shouting next to 16px body copy — but it is a
  /// scale exception, so it is named rather than left as a bare literal.
  static const double button = 15;

  /// Leading multiplier for display/headline sizes.
  static const double displayHeight = 1.1;

  /// Leading multiplier for body copy.
  static const double bodyHeight = 1.5;

  // Letter spacing — negative tightens large display type, positive opens up
  // small all-caps-ish labels.
  static const double trackDisplay1 = -0.8;
  static const double trackDisplay2 = -0.6;
  static const double trackDisplay3 = -0.4;
  static const double trackHeadline1 = -0.3;
  static const double trackHeadline2 = -0.2;
  static const double trackTitle1 = -0.2;
  static const double trackButton = 0.2;
}
