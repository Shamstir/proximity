import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0A0A0A);
  static const Color card = Color(0xFF141414);
  static const Color primary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFF6B6B6B);
  static const Color accent = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFF2A2A2A);
}

class AppTextStyles {
  static TextStyle get displayLarge =>
      GoogleFonts.inter(
        fontSize: 48,
        fontWeight: FontWeight.w200,
        color: AppColors.primary,
        letterSpacing: -1.5,
      );

  static TextStyle get heading =>
      GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w300,
        color: AppColors.primary,
        letterSpacing: -0.5,
      );

  static TextStyle get subHeading =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.secondary,
        letterSpacing: 3,
      );

  static TextStyle get body =>
      GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.primary,
        height: 1.5,
      );

  static TextStyle get caption =>
      GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.secondary,
        letterSpacing: 0.5,
      );

  static TextStyle get button =>
      GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.primary,
        letterSpacing: 2,
      );
}

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    surface: AppColors.surface,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    iconTheme: IconThemeData(color: AppColors.primary),
  ),
  dividerColor: AppColors.divider,
  cardColor: AppColors.card,
);