import 'package:flutter/material.dart';

class HackerTheme {
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color primary = Color(0xFF00FF41); // Matrix Green
  static const Color error = Color(0xFFFF003C); // Cyberpunk Red
  static const Color textMain = Color(0xFF00FF41);
  static const Color textMuted = Color(0xFF008F11);

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        surface: surface,
        error: error,
      ),
      fontFamily: 'Courier',
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: primary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
          letterSpacing: 2.0,
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textMain, fontFamily: 'Courier', fontSize: 16),
        bodyMedium: TextStyle(color: textMain, fontFamily: 'Courier', fontSize: 14),
        titleLarge: TextStyle(color: primary, fontFamily: 'Courier', fontSize: 22, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: primary, fontFamily: 'Courier', fontSize: 18),
        labelLarge: TextStyle(color: background, fontFamily: 'Courier', fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: background,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: primary),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: textMuted, width: 1),
          borderRadius: BorderRadius.zero,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }
}
