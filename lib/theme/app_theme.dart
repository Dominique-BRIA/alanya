import 'package:flutter/material.dart';

/// Palette inspirée des motifs africains du logo Alanya :
/// terre cuite / brun chocolat, crème, accents vert forêt.
class AppColors {
  static const Color terracotta = Color(0xFF8A4B2B); // brun terre cuite (primaire)
  static const Color chocolate = Color(0xFF4A2C1A); // brun foncé
  static const Color clay = Color(0xFFC8895E); // brun clair
  static const Color cream = Color(0xFFF5EFE6); // fond crème
  static const Color forest = Color(0xFF2E7D32); // vert accent
  static const Color sand = Color(0xFFEADBC8);
  static const Color ink = Color(0xFF2B1B12);
  static const Color tickBlue = Color(0xFF53BDE5); // coches "lu" (style WhatsApp)
  static const Color fabPrimary = Color(0xFFC04D29); // bouton flottant principal
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.terracotta,
        primary: AppColors.terracotta,
        secondary: AppColors.forest,
        surface: AppColors.cream,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.cream,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.terracotta,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.terracotta),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.sand),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.sand),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.terracotta, width: 2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.chocolate,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
