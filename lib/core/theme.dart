import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Premium Dark Theme Palette (Slate & Radiant Violet Accent)
  static const Color _darkBackground = Color(0xFF0F0E17);
  static const Color _darkSurface = Color(0xFF161424);
  static const Color _darkSurfaceVariant = Color(0xFF232038);
  static const Color _darkPrimary = Color(0xFF9E86FF);
  static const Color _darkSecondary = Color(0xFFD67BFF);
  static const Color _darkTertiary = Color(0xFFFF8E3C);
  static const Color _darkError = Color(0xFFFF5252);
  static const Color _darkTextPrimary = Color(0xFFFFFEFE);
  static const Color _darkTextSecondary = Color(0xFFA7A5C6);

  // Premium Light Theme Palette (Warm Alabaster & Indigo Accent)
  static const Color _lightBackground = Color(0xFFF9F8F6);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceVariant = Color(0xFFEEECED);
  static const Color _lightPrimary = Color(0xFF5B3CFF);
  static const Color _lightSecondary = Color(0xFFB942FF);
  static const Color _lightTertiary = Color(0xFFE45826);
  static const Color _lightError = Color(0xFFD32F2F);
  static const Color _lightTextPrimary = Color(0xFF0D0D1A);
  static const Color _lightTextSecondary = Color(0xFF6B6A82);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkBackground,
      colorScheme: const ColorScheme.dark(
        surface: _darkSurface,
        onSurface: _darkTextPrimary,
        surfaceContainerHighest: _darkSurfaceVariant,
        onSurfaceVariant: _darkTextSecondary,
        primary: _darkPrimary,
        onPrimary: _darkBackground,
        secondary: _darkSecondary,
        onSecondary: _darkBackground,
        tertiary: _darkTertiary,
        onError: _darkBackground,
        error: _darkError,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: _darkTextPrimary,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: _darkTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _darkSurfaceVariant, width: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurface,
        hintStyle: const TextStyle(color: _darkTextSecondary, fontSize: 15),
        labelStyle: const TextStyle(color: _darkTextSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkSurfaceVariant, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkSurfaceVariant, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkError, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkPrimary,
          foregroundColor: _darkBackground,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _darkPrimary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBackground,
      colorScheme: const ColorScheme.light(
        surface: _lightSurface,
        onSurface: _lightTextPrimary,
        surfaceContainerHighest: _lightSurfaceVariant,
        onSurfaceVariant: _lightTextSecondary,
        primary: _lightPrimary,
        onPrimary: _lightSurface,
        secondary: _lightSecondary,
        onSecondary: _lightSurface,
        tertiary: _lightTertiary,
        onError: _lightSurface,
        error: _lightError,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: _lightTextPrimary,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: _lightTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _lightSurfaceVariant, width: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurface,
        hintStyle: const TextStyle(color: _lightTextSecondary, fontSize: 15),
        labelStyle: const TextStyle(color: _lightTextSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightSurfaceVariant, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightSurfaceVariant, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightError, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: _lightSurface,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _lightPrimary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
