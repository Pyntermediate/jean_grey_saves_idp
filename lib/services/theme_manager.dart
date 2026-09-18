import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager instance = ThemeManager._internal();
  ThemeManager._internal() {
    _loadThemePreference();
  }

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('is_dark_theme') ?? true;
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_dark_theme', isDarkMode);
    } catch (_) {}
  }

  // ── Understated, Professional Color Tokens ─────────────────────────────────
  static const Color accentBlue   = Color(0xFF2563EB); // Royal Blue
  static const Color accentRed    = Color(0xFFDC2626); // Emergency Red
  static const Color accentGreen  = Color(0xFF16A34A); // Success Green
  static const Color accentAmber  = Color(0xFFD97706); // Amber
  static const Color accentSlate  = Color(0xFF64748B); // Slate

  // Light Mode Colors
  static const Color lightBg          = Color(0xFFF5F5F5);
  static const Color lightSurface     = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt  = Color(0xFFEEEEEE);
  static const Color lightBorder      = Color(0xFFE0E0E0);
  static const Color lightText        = Color(0xFF111111);
  static const Color lightTextMuted   = Color(0xFF757575);

  // Dark Mode Colors
  static const Color darkBg           = Color(0xFF000000);
  static const Color darkSurface      = Color(0xFF121212);
  static const Color darkSurfaceAlt   = Color(0xFF1E1E1E);
  static const Color darkBorder       = Color(0xFF333333);
  static const Color darkText         = Color(0xFFE0E0E0);
  static const Color darkTextMuted    = Color(0xFF9E9E9E);

  // Dark Theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      cardColor: darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: accentBlue,
        secondary: accentRed,
        surface: darkSurface,
        surfaceContainerHighest: darkSurfaceAlt,
        onSurface: darkText,
        outline: darkBorder,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: darkText),
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: darkText,
        displayColor: darkText,
      ),
      dividerColor: darkBorder,
    );
  }

  // Light Theme (100% White & Crisp Slate, zero navy)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      cardColor: lightSurface,
      colorScheme: const ColorScheme.light(
        primary: accentBlue,
        secondary: accentRed,
        surface: lightSurface,
        surfaceContainerHighest: lightSurfaceAlt,
        onSurface: lightText,
        outline: lightBorder,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: lightText),
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: lightText,
        displayColor: lightText,
      ),
      dividerColor: lightBorder,
    );
  }
}
