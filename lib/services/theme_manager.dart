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

  bool _isDynamicBackgroundEnabled = true;
  bool get isDynamicBackgroundEnabled => _isDynamicBackgroundEnabled;

  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('is_dark_theme') ?? true;
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      _isDynamicBackgroundEnabled = prefs.getBool('is_dynamic_bg_enabled') ?? true;
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

  Future<void> toggleDynamicBackground() async {
    _isDynamicBackgroundEnabled = !_isDynamicBackgroundEnabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_dynamic_bg_enabled', _isDynamicBackgroundEnabled);
    } catch (_) {}
  }

  // ── Aurora Atmosphere & Frosted Glass Tokens (Stitch Spec) ───────────
  static const Color accentCyan         = Color(0xFF06B6D4); // Stitch Aurora Cyan (rgb(6, 182, 212))
  static const Color accentCyanNeon     = Color(0xFF22D3EE); // Stitch Aurora Neon (rgb(34, 211, 238))
  static const Color accentTeal         = Color(0xFF14B8A6); // Stitch Teal Bloom
  static const Color accentBlue         = Color(0xFF0EA5E9); // Sky / Electric Blue
  static const Color accentElectricBlue = Color(0xFF0072FF); // Deep Electric Blue
  static const Color accentRed          = Color(0xFFFF2A4B); // Fiery Distress SOS Red
  static const Color accentGreen        = Color(0xFF10B981); // Emerald Bloom (rgb(16, 185, 129))
  static const Color accentAmber        = Color(0xFFFF5E3A); // Distress Orange / Flame
  static const Color accentSlate        = Color(0xFF64748B); // Slate Muted

  // Light Mode Colors
  static const Color lightBg          = Color(0xFFF8FAFC);
  static const Color lightSurface     = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt  = Color(0xFFF1F5F9);
  static const Color lightBorder      = Color(0xFFE2E8F0);
  static const Color lightText        = Color(0xFF0F172A);
  static const Color lightTextMuted   = Color(0xFF64748B);

  // Dark Mode Colors (Stitch #0B1015 Base OLED Slate & 1px Frosted Glass)
  static const Color darkBg           = Color(0xFF0B1015); // Base OLED Slate (#0b1015)
  static const Color darkSurface      = Color(0xFF121820); // Base Inactive Glass Surface (rgba(18, 24, 32, ...))
  static const Color darkSurfaceAlt   = Color(0xFF182230); // Elevated Glass Surface
  static const Color darkBorder       = Color(0x14FFFFFF); // 1px Frosted Border (rgba(255, 255, 255, 0.08))
  static const Color darkBorderSheen  = Color(0x4006B6D4); // 1px Cyan Frosted Sheen (rgba(6, 182, 212, 0.25))
  static const Color darkText         = Color(0xFFF8FAFC); // Refined High-Contrast Crisp White
  static const Color darkTextMuted    = Color(0xFF94A3B8); // Refined Contrast Slate Text

  // Dark Theme
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      cardColor: darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: darkText),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: darkText,
        displayColor: darkText,
      ),
      dividerColor: darkBorder,
    );
  }

  // Light Theme (Clean Crisp Glass)
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: lightText),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: lightText,
        displayColor: lightText,
      ),
      dividerColor: lightBorder,
    );
  }
}
