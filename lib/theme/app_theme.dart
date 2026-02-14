import 'package:flutter/material.dart';

class AppTheme {
  static const Color _seed = Color(0xFF0F766E);
  static const Color _lightSurface = Color(0xFFF4F8F7);
  static const Color _lightCard = Color(0xFFFFFFFF);
  static const Color _darkSurface = Color(0xFF0F1415);
  static const Color _darkCard = Color(0xFF182022);

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? _darkSurface : _lightSurface,
      cardTheme: CardThemeData(
        color: isDark ? _darkCard : _lightCard,
        elevation: isDark ? 1 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        indicatorColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
      ),
      textTheme: _textTheme(brightness),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color primaryText = isDark ? const Color(0xFFE6F0EE) : const Color(0xFF1D2C2A);
    final Color secondaryText = isDark ? const Color(0xFFB3C4C0) : const Color(0xFF4A5C59);

    return TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: primaryText,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: primaryText,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primaryText,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.35,
        color: primaryText,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: secondaryText,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: secondaryText,
      ),
    );
  }
}
