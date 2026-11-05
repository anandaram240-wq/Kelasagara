import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(primary: AppColors.primary, secondary: AppColors.violet, surface: AppColors.surface, error: AppColors.red),
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface, elevation: 0, centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textHead),
      iconTheme: const IconThemeData(color: AppColors.textHead),
    ),
    textTheme: TextTheme(
      displayLarge: GoogleFonts.sora(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textHead, letterSpacing: -0.5),
      headlineLarge: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textHead),
      headlineMedium: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textHead),
      titleLarge: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
      bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textBody),
      bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textBody),
      bodySmall: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textLight),
    ),
    cardTheme: CardThemeData(color: AppColors.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)), margin: EdgeInsets.zero),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: AppColors.surface2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), hintStyle: TextStyle(color: AppColors.textFaint)),
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: AppColors.surface, selectedItemColor: AppColors.primary, unselectedItemColor: AppColors.textFaint, type: BottomNavigationBarType.fixed, elevation: 0),
  );
}
