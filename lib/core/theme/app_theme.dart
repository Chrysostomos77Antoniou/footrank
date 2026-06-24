import 'package:flutter/material.dart';
import 'package:footrank/core/theme/app_colors.dart';

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
      onSurface: isDark ? const Color(0xFFECEEF1) : const Color(0xFF000000),
    );

    final cardColor = isDark ? _darkCard : _lightCard;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE3E6EB);

    final onSurface = scheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? _darkBg : _lightBg,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'Manrope',
      textTheme: _textTheme(onSurface),

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: isDark ? _darkBg : _lightBg,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontFamily: 'Sora',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: scheme.onSurface,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      dividerTheme: DividerThemeData(color: borderColor, thickness: 1),
    );
  }

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  /// Sora for the big expressive headings, Manrope for everything readable.
  static TextTheme _textTheme(Color onSurface) {
    const display = 'Sora';
    TextStyle h(double size, FontWeight w, double spacing) => TextStyle(
          fontFamily: display,
          fontSize: size,
          fontWeight: w,
          letterSpacing: spacing,
          height: 1.1,
          color: onSurface,
        );
    TextStyle body(double size, FontWeight w) => TextStyle(
          fontFamily: 'Manrope',
          fontSize: size,
          fontWeight: w,
          height: 1.5,
          color: onSurface,
        );
    return TextTheme(
      displayLarge: h(34, FontWeight.w800, -0.8),
      displayMedium: h(28, FontWeight.w800, -0.6),
      displaySmall: h(24, FontWeight.w700, -0.4),
      headlineMedium: h(22, FontWeight.w700, -0.3),
      headlineSmall: h(20, FontWeight.w700, -0.2),
      titleLarge: h(18, FontWeight.w700, -0.2),
      titleMedium: body(16, FontWeight.w700),
      titleSmall: body(14, FontWeight.w600),
      bodyLarge: body(16, FontWeight.w500),
      bodyMedium: body(14, FontWeight.w500),
      bodySmall: body(12, FontWeight.w500),
      labelLarge: body(14, FontWeight.w700),
      labelMedium: body(12, FontWeight.w600),
      labelSmall: body(11, FontWeight.w600),
    );
  }
}
