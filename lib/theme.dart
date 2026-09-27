import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HackerTheme {
  static const Color background = Color(0xFF030504);
  static const Color surface = Color(0xFF0A120D);
  static const Color primary = Color(0xFF00FF41); // Classic Matrix Green
  static const Color primaryGlow = Color(0x6600FF41); 
  static const Color secondary = Color(0xFF00FFCC); // Cyan accent
  static const Color error = Color(0xFFFF0055); // Cyberpunk Red
  static const Color textMain = Color(0xFFE0FFE8);
  static const Color textMuted = Color(0xFF008F11);
  static const Color borderBright = Color(0xFF00FF41);
  static const Color borderDim = Color(0xFF004411);

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
      ),
      textTheme: GoogleFonts.shareTechMonoTextTheme().copyWith(
        bodyLarge: GoogleFonts.shareTechMono(color: textMain, fontSize: 16),
        bodyMedium: GoogleFonts.shareTechMono(color: textMain, fontSize: 14),
        titleLarge: GoogleFonts.shareTechMono(color: primary, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        titleMedium: GoogleFonts.shareTechMono(color: secondary, fontSize: 18),
        labelLarge: GoogleFonts.shareTechMono(color: background, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: primary),
        titleTextStyle: GoogleFonts.shareTechMono(
          color: primary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 3.0,
          shadows: [
            const Shadow(color: primaryGlow, blurRadius: 10),
          ],
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: background,
          elevation: 8,
          shadowColor: primaryGlow,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            side: BorderSide(color: primary, width: 2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.shareTechMono(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: error,
          side: const BorderSide(color: error, width: 2),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.shareTechMono(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderDim, width: 1.5),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: background,
        elevation: 12,
        splashColor: secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: borderBright, width: 2),
        ),
      ),
    );
  }
}
