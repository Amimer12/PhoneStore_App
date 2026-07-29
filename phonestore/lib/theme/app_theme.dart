import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Gold / Black / White palette — clean, premium feel for a boutique shop admin.
class AppColors {
  static const gold = Color(0xFFC9A227);
  static const goldLight = Color(0xFFE7CD7A);
  static const black = Color(0xFF0B0B0B);
  static const charcoal = Color(0xFF1E1E1E);
  static const white = Color(0xFFFFFFFF);
  static const offWhite = Color(0xFFF7F6F3);
  static const grey = Color(0xFF9A9A9A);
  static const danger = Color(0xFFB3261E);
  static const success = Color(0xFF2E7D32);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final bodyFont = GoogleFonts.manropeTextTheme(base.textTheme);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.offWhite,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.gold,
        secondary: AppColors.black,
        surface: AppColors.white,
        error: AppColors.danger,
      ),
      textTheme: bodyFont.copyWith(
        // Headline-ish styles use the serif display font for a boutique feel;
        // everything else stays on the clean sans body font for readability.
        headlineLarge: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, fontSize: 30, color: AppColors.black),
        headlineMedium: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700, fontSize: 24, color: AppColors.black),
        headlineSmall: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600, fontSize: 20, color: AppColors.black),
        titleLarge: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600, fontSize: 18, color: AppColors.black),
      ).apply(
        bodyColor: AppColors.black,
        displayColor: AppColors.black,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.playfairDisplay(
          color: AppColors.gold,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.black,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.black,
        indicatorColor: AppColors.gold.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? AppColors.gold : AppColors.grey,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.gold : AppColors.grey);
        }),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE7E5E0), thickness: 1),
    );
  }
}
