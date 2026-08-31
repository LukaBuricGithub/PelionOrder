import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App theme, mirroring the ikasa app's clean, high-contrast, touch-friendly
/// Material 3 look — intentionally optimized for fast, reliable use on the
/// restaurant floor rather than visual flourish.
class AppTheme {
  /// Applies the Inter font to a base [TextTheme] (keeps each style's size,
  /// weight and colour, just swaps the family). Inter reads like a cleaner
  /// Roboto and fully supports Croatian diacritics (č ć đ š ž).
  static TextTheme _interTextTheme(TextTheme base) =>
      GoogleFonts.interTextTheme(base);

  static const _seedBlue = Color(0xFF4A78B4);
  static const _lightScaffold = Color(0xFFF6F8FC);
  static const _darkScaffold = Color(0xFF0F1724);
  static const _darkSurface = Color(0xFF162133);
  static const _darkSurfaceHigh = Color(0xFF223047);
  static const _darkOutline = Color(0xFF344761);
  static const _darkOnSurfaceVariant = Color(0xFFB3C1D7);
  static const _darkPrimary = Color(0xFF5A80B8);
  static const _darkPrimaryContainer = Color(0xFF2A4262);
  static const _darkSecondaryContainer = Color(0xFF213652);
  static const _darkOnSecondaryContainer = Color(0xFFDCE8FF);

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seedBlue,
      brightness: Brightness.light,
    ).copyWith(
      surface: Colors.white,
      surfaceContainerHighest: const Color(0xFFE9EEF7),
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = _interTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: _lightScaffold,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _lightScaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF81AEFF),
      brightness: Brightness.dark,
    ).copyWith(
      primary: _darkPrimary,
      onPrimary: Colors.white,
      primaryContainer: _darkPrimaryContainer,
      surface: _darkSurface,
      surfaceContainerHighest: _darkSurfaceHigh,
      secondaryContainer: _darkSecondaryContainer,
      onSecondaryContainer: _darkOnSecondaryContainer,
      outlineVariant: _darkOutline,
      onSurfaceVariant: _darkOnSurfaceVariant,
      shadow: Colors.black,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final textTheme = _interTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: _darkScaffold,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _darkScaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.7),
    );
  }
}
