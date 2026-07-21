import 'package:flutter/material.dart';

/// Calm, low-sensory palette and typography.
///
/// Design goals for an autism-friendly experience: soft muted colours (no harsh
/// reds or high-saturation), generous spacing, large readable text, and no
/// flashing or sudden motion.
class AppColors {
  static const bg = Color(0xFFF7F6F2); // warm off-white
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFF5B8A72); // soft sage green
  static const primaryDark = Color(0xFF3F6B57);
  static const accent = Color(0xFF6C8EBF); // muted blue
  static const text = Color(0xFF2E3330);
  static const textSoft = Color(0xFF7A817C);
  static const border = Color(0xFFE3E1DA);
}

ThemeData buildTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );
}
