import 'package:flutter/material.dart';

/// Color palette and theme styling matching the Zed editor dark aesthetic.
class AppTheme {
  static const Color background = Color(0xFF18181B); // Zinc 900
  static const Color surface = Color(0xFF27272A);    // Zinc 800
  static const Color surfaceLight = Color(0xFF3F3F46); // Zinc 700
  static const Color border = Color(0xFF3F3F46);     // Zinc 700
  static const Color primary = Color(0xFF3B82F6);    // Blue 500
  static const Color primaryAccent = Color(0xFF60A5FA); // Blue 400
  static const Color thoughtBackground = Color(0xFF1E293B); // Slate 800
  static const Color thoughtBorder = Color(0xFF334155); // Slate 700
  static const Color success = Color(0xFF10B981);    // Emerald 500
  static const Color warning = Color(0xFFF59E0B);    // Amber 500
  static const Color danger = Color(0xFFEF4444);     // Red 500
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textSecondary = Color(0xFFA1A1AA);

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: primary,
    cardColor: surface,
    dividerColor: border,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primaryAccent,
      surface: surface,
      error: danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: border, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}
