import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';
import 'package:footrank/core/theme/app_tokens.dart';

/// Route transition: incoming page fades in while drifting up slightly;
/// the page underneath settles back. Subtle spatial continuity instead of a
/// hard cut — applied app-wide via [ThemeData.pageTransitionsTheme].
class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.easeOut,
      reverseCurve: AppMotion.easeIn,
    );
    final covered = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.easeOut,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, AppMotion.pageSlideOffset),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          // Page being covered recedes slightly for depth.
          opacity: Tween<double>(begin: 1, end: AppOpacity.coveredPage)
              .animate(covered),
          child: child,
        ),
      ),
    );
  }
}

/// Component-tier theme.
///
/// This file consumes semantic tokens ([AppSemantic], [AppOpacity],
/// [AppTypeScale], [AppFonts], [AppIconSize], [AppElevation]) and colours from
/// [AppColors] — and nothing else. If you find yourself typing a number or a
/// `Color(0x...)` here, it belongs in `app_tokens.dart` or `app_colors.dart`
/// first. The token file calls itself the single source of truth; this file is
/// the one that has to prove it.
class AppTheme {
  AppTheme._();

  // Surface colors
  static const _lightBg = AppColors.lightBg;
  static const _lightCard = AppColors.lightCard;
  static const _darkBg = AppColors.darkBg;
  static const _darkCard = AppColors.darkCard;

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // Bright lime in dark mode; deep green in light mode (more readable on white).
    final accent = isDark ? AppColors.lime : AppColors.limeDeep;
    final onAccent = isDark ? AppColors.navy : Colors.white;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
    ).copyWith(
      surface: isDark ? _darkBg : _lightBg,
      // Pin high-contrast text colors so nothing washes out, esp. in light mode.
      onSurface: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
    );

    final cardColor = isDark ? _darkCard : _lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final onSurface = scheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? _darkBg : _lightBg,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: AppFonts.body,
      textTheme: _textTheme(onSurface),

      // Smooth, consistent screen-to-screen motion on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.linux: _FadeSlidePageTransitionsBuilder(),
        },
      ),

      // Icon-only buttons must still give a full-size touch target.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize:
              const Size(AppSemantic.minTapTarget, AppSemantic.minTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),

      appBarTheme: AppBarTheme(
        elevation: AppElevation.flat,
        scrolledUnderElevation: AppElevation.flat,
        centerTitle: false,
        backgroundColor: isDark ? _darkBg : _lightBg,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: AppTypeScale.headline2,
          fontWeight: FontWeight.w800,
          letterSpacing: AppTypeScale.trackDisplay3,
          color: scheme.onSurface,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: AppElevation.flat,
        margin: EdgeInsets.zero,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSemantic.cardRadius),
          side: BorderSide(color: borderColor),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSemantic.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
          ),
          textStyle: const TextStyle(
              fontFamily: AppFonts.display,
              fontSize: AppTypeScale.button,
              fontWeight: FontWeight.w700,
              letterSpacing: AppTypeScale.trackButton),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSemantic.buttonHeight),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
          ),
          textStyle: const TextStyle(
              fontSize: AppTypeScale.button, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize:
              const Size(AppSemantic.minTapTarget, AppSemantic.minTapTarget),
          textStyle: const TextStyle(
              fontSize: AppTypeScale.label1, fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSemantic.controlRadius),
          borderSide: BorderSide(
              color: accent, width: AppSemantic.focusedBorderWidth),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: AppSemantic.navBarHeight,
        elevation: AppElevation.flat,
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: AppOpacity.navIndicator),
        // Selected tab reads clearly: accent + heavier weight, not color alone.
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: AppTypeScale.label2,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? accent
                : onSurface.withValues(alpha: AppOpacity.navUnselected),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? accent
                : onSurface.withValues(alpha: AppOpacity.navUnselected),
          );
        }),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSemantic.chipRadius),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSemantic.overlayRadius),
        ),
      ),

      dividerTheme: DividerThemeData(
          color: borderColor, thickness: AppSemantic.borderWidth),
    );
  }

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  /// Sora for the big expressive headings, Manrope for everything readable.
  static TextTheme _textTheme(Color onSurface) {
    TextStyle h(double size, FontWeight w, double spacing) => TextStyle(
          fontFamily: AppFonts.display,
          fontSize: size,
          fontWeight: w,
          letterSpacing: spacing,
          height: AppTypeScale.displayHeight,
          color: onSurface,
        );
    TextStyle body(double size, FontWeight w) => TextStyle(
          fontFamily: AppFonts.body,
          fontSize: size,
          fontWeight: w,
          height: AppTypeScale.bodyHeight,
          color: onSurface,
        );
    return TextTheme(
      displayLarge:
          h(AppTypeScale.display1, FontWeight.w800, AppTypeScale.trackDisplay1),
      displayMedium:
          h(AppTypeScale.display2, FontWeight.w800, AppTypeScale.trackDisplay2),
      displaySmall:
          h(AppTypeScale.display3, FontWeight.w700, AppTypeScale.trackDisplay3),
      headlineMedium: h(
          AppTypeScale.headline1, FontWeight.w700, AppTypeScale.trackHeadline1),
      headlineSmall: h(
          AppTypeScale.headline2, FontWeight.w700, AppTypeScale.trackHeadline2),
      titleLarge:
          h(AppTypeScale.title1, FontWeight.w700, AppTypeScale.trackTitle1),
      titleMedium: body(AppTypeScale.title2, FontWeight.w700),
      titleSmall: body(AppTypeScale.title3, FontWeight.w600),
      bodyLarge: body(AppTypeScale.body1, FontWeight.w500),
      bodyMedium: body(AppTypeScale.body2, FontWeight.w500),
      bodySmall: body(AppTypeScale.body3, FontWeight.w500),
      labelLarge: body(AppTypeScale.label1, FontWeight.w700),
      labelMedium: body(AppTypeScale.label2, FontWeight.w600),
      labelSmall: body(AppTypeScale.label3, FontWeight.w600),
    );
  }
}
