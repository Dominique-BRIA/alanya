import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// ALANYA DESIGN SYSTEM — Premium African-Inspired Theme
// =============================================================================
// Palette : terre cuite, brun chocolat, sable, vert forêt, or doux.
// Inspirée des motifs tissés africains et de la terre rouge camerounaise.
// =============================================================================

// ---------------------------------------------------------------------------
// COULEURS PRINCIPALES
// ---------------------------------------------------------------------------
class AlanyaColors {
  AlanyaColors._();

  // --- Terre cuite (Primary) ---
  static const Color terracotta      = Color(0xFFB85C38);
  static const Color terracottaLight = Color(0xFFD4845E);
  static const Color terracottaDark  = Color(0xFF8A3A1E);

  // --- Brun chocolat (Secondary) ---
  static const Color chocolate      = Color(0xFF5C3D2E);
  static const Color chocolateLight = Color(0xFF8B6B5A);

  // --- Vert forêt (Accent) ---
  static const Color forest      = Color(0xFF2D6A4F);
  static const Color forestLight = Color(0xFF52B788);
  static const Color forestDark  = Color(0xFF1B4332);

  // --- Sable & Crème (Surface) ---
  static const Color sand       = Color(0xFFF0E6D8);
  static const Color cream      = Color(0xFFFAF6F0);
  static const Color warmWhite  = Color(0xFFFFFCF8);

  // --- Or doux ---
  static const Color gold       = Color(0xFFD4A574);
  static const Color goldLight  = Color(0xFFF0D5B8);

  // --- Neutres chauds ---
  static const Color ink        = Color(0xFF1A1210);
  static const Color inkLight   = Color(0xFF3D322C);
  static const Color grey50     = Color(0xFFFAF8F6);
  static const Color grey100    = Color(0xFFF5F0EB);
  static const Color grey200    = Color(0xFFE8DFD6);
  static const Color grey300    = Color(0xFFD4C8BC);
  static const Color grey400    = Color(0xFFB0A090);
  static const Color grey500    = Color(0xFF8C7A68);
  static const Color grey600    = Color(0xFF6B5A4A);
  static const Color grey700    = Color(0xFF4A3D32);
  static const Color grey800    = Color(0xFF2E241C);
  static const Color grey900    = Color(0xFF1A1210);

  // --- Sémantiques ---
  static const Color success    = Color(0xFF2D6A4F);
  static const Color successBg  = Color(0xFFE8F5E9);
  static const Color warning    = Color(0xFFE8A317);
  static const Color warningBg  = Color(0xFFFFF8E1);
  static const Color error      = Color(0xFFC62828);
  static const Color errorBg    = Color(0xFFFFEBEE);
  static const Color info       = Color(0xFF1565C0);
  static const Color infoBg     = Color(0xFFE3F2FD);

  // --- Chat ---
  static const Color bubbleMe     = Color(0xFFB85C38);
  static const Color bubbleOther  = Color(0xFFFFFFFF);
  static const Color tickDelivered = Color(0xFF9E9E9E);
  static const Color tickRead     = Color(0xFF52B788);

  // --- Avatar gradients ---
  static const List<Color> avatarGradients = [
    Color(0xFFB85C38),
    Color(0xFFD4845E),
    Color(0xFF5C3D2E),
    Color(0xFF2D6A4F),
    Color(0xFFD4A574),
    Color(0xFF8B6B5A),
    Color(0xFF52B788),
    Color(0xFFE8A317),
  ];
}

// ---------------------------------------------------------------------------
// LIGHT THEME
// ---------------------------------------------------------------------------
class AlanyaTheme {
  AlanyaTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: AlanyaColors.terracotta,
      onPrimary: Colors.white,
      primaryContainer: AlanyaColors.terracottaLight,
      onPrimaryContainer: AlanyaColors.terracottaDark,
      secondary: AlanyaColors.forest,
      onSecondary: Colors.white,
      secondaryContainer: AlanyaColors.forestLight,
      onSecondaryContainer: AlanyaColors.forestDark,
      tertiary: AlanyaColors.gold,
      onTertiary: Colors.white,
      surface: AlanyaColors.warmWhite,
      onSurface: AlanyaColors.ink,
      onSurfaceVariant: AlanyaColors.grey600,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AlanyaColors.grey50,
      surfaceContainer: AlanyaColors.grey100,
      surfaceContainerHigh: AlanyaColors.grey200,
      surfaceContainerHighest: AlanyaColors.grey300,
      outline: AlanyaColors.grey300,
      outlineVariant: AlanyaColors.grey200,
      error: AlanyaColors.error,
      onError: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AlanyaColors.cream,

      // --- Typography ---
      textTheme: _buildTextTheme(Brightness.light),

      // --- AppBar ---
      appBarTheme: AppBarTheme(
        backgroundColor: AlanyaColors.warmWhite,
        foregroundColor: AlanyaColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.ink,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: AlanyaColors.ink),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      // --- NavigationBar ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AlanyaColors.warmWhite,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AlanyaColors.terracotta.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AlanyaColors.terracotta, size: 24);
          }
          return IconThemeData(color: AlanyaColors.grey400, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AlanyaColors.terracotta,
              letterSpacing: 0.2,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AlanyaColors.grey400,
          );
        }),
      ),

      // --- ElevatedButton ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AlanyaColors.terracotta,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // --- OutlinedButton ---
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AlanyaColors.terracotta,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: AlanyaColors.terracotta.withValues(alpha: 0.4)),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // --- TextButton ---
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AlanyaColors.terracotta,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // --- InputDecoration ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(
          color: AlanyaColors.grey400,
          fontWeight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AlanyaColors.grey200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AlanyaColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.terracotta, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AlanyaColors.error.withValues(alpha: 0.5)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.error, width: 1.5),
        ),
      ),

      // --- Card ---
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AlanyaColors.grey200, width: 0.5),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // --- Divider ---
      dividerTheme: DividerThemeData(
        color: AlanyaColors.grey200,
        thickness: 0.5,
        space: 1,
      ),

      // --- SnackBar ---
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AlanyaColors.ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // --- BottomSheet ---
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AlanyaColors.warmWhite,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: AlanyaColors.grey300,
      ),

      // --- Dialog ---
      dialogTheme: DialogThemeData(
        backgroundColor: AlanyaColors.warmWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AlanyaColors.ink,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AlanyaColors.grey600,
        ),
      ),

      // --- Chip ---
      chipTheme: ChipThemeData(
        backgroundColor: AlanyaColors.grey100,
        selectedColor: AlanyaColors.terracotta.withValues(alpha: 0.12),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AlanyaColors.grey700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // --- ListTile ---
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AlanyaColors.ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AlanyaColors.grey500,
        ),
      ),

      // --- FloatingActionButton ---
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AlanyaColors.terracotta,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // --- ProgressIndicator ---
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AlanyaColors.terracotta,
        linearTrackColor: AlanyaColors.sand,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DARK THEME
  // ---------------------------------------------------------------------------
  static ThemeData get dark {
    const darkBg = Color(0xFF121010);
    const darkSurface = Color(0xFF1E1B18);
    const darkSurfaceHigh = Color(0xFF2A2520);

    final colorScheme = ColorScheme.dark(
      primary: AlanyaColors.terracottaLight,
      onPrimary: AlanyaColors.terracottaDark,
      primaryContainer: AlanyaColors.terracottaDark,
      onPrimaryContainer: AlanyaColors.terracottaLight,
      secondary: AlanyaColors.forestLight,
      onSecondary: AlanyaColors.forestDark,
      secondaryContainer: AlanyaColors.forestDark,
      onSecondaryContainer: AlanyaColors.forestLight,
      tertiary: AlanyaColors.goldLight,
      onTertiary: AlanyaColors.ink,
      surface: darkSurface,
      onSurface: const Color(0xFFE8E0D8),
      onSurfaceVariant: const Color(0xFFB0A090),
      surfaceContainerLowest: const Color(0xFF0E0C0A),
      surfaceContainerLow: darkSurface,
      surfaceContainer: darkSurfaceHigh,
      surfaceContainerHigh: const Color(0xFF352F28),
      surfaceContainerHighest: const Color(0xFF403830),
      outline: const Color(0xFF403830),
      outlineVariant: const Color(0xFF2A2520),
      error: const Color(0xFFEF5350),
      onError: Colors.white,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      textTheme: _buildTextTheme(Brightness.dark),

      appBarTheme: AppBarTheme(
        backgroundColor: darkBg,
        foregroundColor: const Color(0xFFE8E0D8),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE8E0D8),
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkBg,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: AlanyaColors.terracottaLight.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AlanyaColors.terracottaLight, size: 24);
          }
          return const IconThemeData(color: Color(0xFF6B5A4A), size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AlanyaColors.terracottaLight,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B5A4A),
          );
        }),
      ),

      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2520), width: 0.5),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2520),
        thickness: 0.5,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2A2520),
        contentTextStyle: const TextStyle(
          color: Color(0xFFE8E0D8),
          fontFamily: 'Inter',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
        dragHandleColor: Color(0xFF403830),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: Color(0xFF6B5A4A)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A2520)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2A2520)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AlanyaColors.terracottaLight, width: 1.5),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AlanyaColors.terracottaLight,
        foregroundColor: AlanyaColors.terracottaDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TYPOGRAPHY (Inter)
  // ---------------------------------------------------------------------------
  static TextTheme _buildTextTheme(Brightness brightness) {
    final Color bodyColor = brightness == Brightness.light
        ? AlanyaColors.ink
        : const Color(0xFFE8E0D8);
    final Color mutedColor = brightness == Brightness.light
        ? AlanyaColors.grey500
        : const Color(0xFF8C7A68);

    return TextTheme(
      // Display
      displayLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: bodyColor,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        letterSpacing: -0.5,
        height: 1.25,
      ),

      // Headline
      headlineLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: bodyColor,
        letterSpacing: -0.3,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: -0.1,
        height: 1.35,
      ),

      // Title
      titleLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0,
        height: 1.4,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.1,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: bodyColor,
        letterSpacing: 0.1,
        height: 1.4,
      ),

      // Body
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: mutedColor,
        letterSpacing: 0.2,
        height: 1.5,
      ),

      // Label
      labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.3,
        height: 1.4,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: bodyColor,
        letterSpacing: 0.4,
        height: 1.4,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: mutedColor,
        letterSpacing: 0.5,
        height: 1.4,
      ),
    );
  }
}
