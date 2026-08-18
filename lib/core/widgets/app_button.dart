import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// The single button.
///
/// The app shipped four primary-emphasis buttons that looked and felt
/// different from each other:
///
/// | impl                | radius | type                | press               | sites |
/// |---------------------|--------|---------------------|---------------------|-------|
/// | themed FilledButton | 12     | Sora 15 w700 +0.2   | ripple              | 37    |
/// | `BrandButton`       | 16     | Manrope 16 w800 0   | scale 0.97 + haptic | 4     |
/// | `AuthPrimaryButton` | 16     | Manrope 16 w800 0   | scale 0.97 + haptic | 5     |
/// | `_PrimaryCta`       | 20     | Sora 18 w800, grad  | scale 0.97 + haptic | 1     |
///
/// `FilledButton` wins on weight of adoption — 37 of the 47 real primary
/// buttons already are one, so converging on it is a theme edit plus ~10
/// migrations, whereas promoting `BrandButton` would mean rewriting 37 sites
/// AND inventing the disabled, focus, ripple and semantics behaviour that the
/// hand-rolled buttons never had. (`PressableScale.onTap` is a non-nullable
/// `VoidCallback`, which is the structural reason none of those three can even
/// express a disabled state.)
///
/// So this wraps the Material buttons — inheriting their accessibility and
/// state machinery for free — and adds back the two things the custom buttons
/// genuinely did better:
///
/// * **A haptic on tap.** Previously only the 10 custom-button sites vibrated,
///   so a themed `FilledButton` felt inert next to a tappable `GlassCard`.
/// * **A first-class loading state.** Eight call sites hand-rolled
///   `_loading ? SizedBox(20x20, CircularProgressIndicator(strokeWidth: 2)) :
///   Text(...)`, each slightly differently, and each one visibly resized the
///   button as it swapped.
enum AppButtonVariant {
  /// Filled brand accent. One per screen — this is the screen's main action.
  primary,

  /// Outlined. Secondary actions that sit beside a primary.
  secondary,

  /// Filled danger. Destructive confirmations only.
  destructive,

  /// Text only. Tertiary/inline actions.
  ghost,
}

class AppButton extends StatelessWidget {
  final String label;

  /// Null disables the button. Ignored while [loading] is true.
  final VoidCallback? onPressed;

  final IconData? icon;

  /// Swaps the label for a spinner and blocks input, without changing size.
  final bool loading;

  final AppButtonVariant variant;

  /// Primary/destructive default to full width (the themed
  /// `minimumSize: Size.fromHeight(52)` already forced this); secondary and
  /// ghost size to their content.
  final bool? fullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
    this.fullWidth,
  });

  bool get _stretches =>
      fullWidth ??
      (variant == AppButtonVariant.primary ||
          variant == AppButtonVariant.destructive);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    void handleTap() {
      // Matches PressableScale's signature feel, so a button and a tappable
      // card no longer respond differently to the same gesture.
      HapticFeedback.selectionClick();
      onPressed!();
    }

    final child = _AnimatedButtonContent(
      label: label,
      icon: icon,
      loading: loading,
    );

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: enabled ? handleTap : null,
          style: _sizeOverride(),
          child: child,
        ),
      AppButtonVariant.destructive => FilledButton(
          onPressed: enabled ? handleTap : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
          ).merge(_sizeOverride()),
          child: child,
        ),
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: enabled ? handleTap : null,
          style: _consistentTypography(OutlinedButton.styleFrom())
              .merge(_sizeOverride()),
          child: child,
        ),
      AppButtonVariant.ghost => TextButton(
          onPressed: enabled ? handleTap : null,
          style: _consistentTypography(TextButton.styleFrom())
              .merge(_sizeOverride()),
          child: child,
        ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, loading' : label,
      child: button,
    );
  }

  /// The themed Outlined/Text buttons inherit `ThemeData.fontFamily`
  /// (Manrope) while FilledButton is explicitly Sora, so a Create/Join pair
  /// rendered in two different typefaces at two weights and trackings.
  ButtonStyle _consistentTypography(ButtonStyle base) => base.merge(
        const ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppFonts.display,
              fontSize: AppTypeScale.button,
              fontWeight: FontWeight.w700,
              letterSpacing: AppTypeScale.trackButton,
            ),
          ),
        ),
      );

  ButtonStyle _sizeOverride() => ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          _stretches
              ? const Size.fromHeight(AppSemantic.buttonHeight)
              : const Size(0, AppSemantic.minTapTarget),
        ),
      );
}

/// Crossfades label <-> spinner without the button resizing underneath the
/// user's finger.
class _AnimatedButtonContent extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;

  const _AnimatedButtonContent({
    required this.label,
    required this.icon,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.quick,
      curve: AppMotion.easeOut,
      child: AnimatedSwitcher(
        duration: AppMotion.quick,
        // AnimatedSwitcher defaults both curves to linear; a scale/fade swap
        // needs real easing or it reads as a glitch rather than a transition.
        switchInCurve: AppMotion.easeOut,
        switchOutCurve: AppMotion.easeIn,
        child: loading
            ? SizedBox(
                key: const ValueKey('loading'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: DefaultTextStyle.of(context).style.color,
                ),
              )
            : Row(
                key: const ValueKey('label'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: AppIconSize.sm),
                    const SizedBox(width: AppSemantic.iconGap),
                  ],
                  Flexible(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
      ),
    );
  }
}
