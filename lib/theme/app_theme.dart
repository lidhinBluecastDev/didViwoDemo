import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// School-demo palette: sunlit classroom teal + soft sky, chalk accent.
abstract final class AppColors {
  static const ink = Color(0xFF12323A);
  static const deepTeal = Color(0xFF0E4A56);
  static const sea = Color(0xFF1F7A88);
  static const sky = Color(0xFF9AD0DA);
  static const mist = Color(0xFFE7F4F6);
  static const chalk = Color(0xFFF2D56B);
  static const chalkDeep = Color(0xFFE0B83A);
  static const cream = Color(0xFFF7FBFC);
  static const error = Color(0xFFB42318);
}

abstract final class AppTheme {
  static ThemeData get light {
    final display = GoogleFonts.frauncesTextTheme();
    final body = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.sea,
        primary: AppColors.deepTeal,
        secondary: AppColors.chalkDeep,
        surface: AppColors.cream,
      ),
      textTheme: body.copyWith(
        displayLarge: display.displayLarge?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
          height: 1.05,
        ),
        displayMedium: display.displayMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
          height: 1.08,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: body.titleLarge?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: body.bodyLarge?.copyWith(
          color: AppColors.ink.withValues(alpha: 0.82),
          height: 1.45,
        ),
        bodyMedium: body.bodyMedium?.copyWith(
          color: AppColors.ink.withValues(alpha: 0.75),
          height: 1.4,
        ),
      ),
    );
  }
}
