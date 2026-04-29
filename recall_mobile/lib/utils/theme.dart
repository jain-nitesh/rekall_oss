import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants.dart';

/// ReKall Brand Design System
///
/// Brand Colors:
/// - Primary Brand: Synapse Indigo (#4F46E5) - Buttons, logo accents, active states
/// - Action/Accent: Recall Cyan (#06B6D4) - High energy, save confirmations, highlights
/// - Background Dark: Deep Space (#0F172A) - Dark mode background (not pure black)
/// - Text Light: Starlight (#F8FAFC) - Primary text on dark backgrounds
/// - Text Secondary: Slate Gray (#94A3B8) - Subtitles, metadata, timestamps
///
/// Design Principles:
/// - Premium digital feel with Synapse Indigo as hero color
/// - Recall Cyan for high-energy moments (used sparingly)
/// - Deep Space for rich dark mode experience
/// - Soft UI: 12-16px border radius, subtle 1px borders, minimal shadows
/// - Inter font family for maximum readability
class AppTheme {
  // Legacy support
  static const Color primaryColor = AppConstants.synapseIndigo;
  static const Color secondaryColor = AppConstants.synapseIndigoLight;

  // Shadow Definitions (Premium depth hierarchy)
  static const List<BoxShadow> shadowSoft = [
    BoxShadow(
      color: Color(0x0A000000), // 4% black
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Color(0x0F000000), // 6% black
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  // Dual-layer soft shadow (for cards)
  static const List<BoxShadow> shadowSoftDual = [
    BoxShadow(
      color: Color(0x08000000), // 3% black
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x04000000), // 2% black
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  // Dual-layer medium shadow (for elevated elements)
  static const List<BoxShadow> shadowMediumDual = [
    BoxShadow(
      color: Color(0x0A000000), // 4% black
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x06000000), // 2.5% black
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];

  // Glow shadow (for interactive elements)
  static BoxShadow glowShadow(Color color) => BoxShadow(
    color: color.withValues(alpha: 0.25),
    blurRadius: 20,
    spreadRadius: 2,
    offset: Offset(0, 4),
  );

  /// Light Theme - Premium Soft UI
  static ThemeData get lightTheme {

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color Scheme - Brand Colors
      colorScheme: ColorScheme.light(
        primary: AppConstants.synapseIndigo,
        onPrimary: AppConstants.white,
        primaryContainer: AppConstants.synapseIndigoLight,
        onPrimaryContainer: AppConstants.deepSpace,

        secondary: AppConstants.recallCyan,
        onSecondary: AppConstants.white,

        tertiary: AppConstants.synapseIndigoDark,
        onTertiary: AppConstants.white,

        error: AppConstants.errorColor,
        onError: AppConstants.white,

        surface: AppConstants.white,
        onSurface: AppConstants.textPrimary,
        surfaceContainerHighest: AppConstants.softWhite,

        outline: AppConstants.borderColor,
        outlineVariant: AppConstants.dividerColor,
      ),

      // Scaffold
      scaffoldBackgroundColor: AppConstants.softWhite,

      // App Bar Theme - Minimal, clean
      appBarTheme: AppBarTheme(
        elevation: AppConstants.elevationNone,
        backgroundColor: AppConstants.white,
        foregroundColor: AppConstants.textPrimary,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(
          color: AppConstants.textPrimary,
          size: 24,
          weight: 300,
          opticalSize: 24,
          fill: 0.0,
        ),
      ),

      // Card Theme - Soft UI with subtle border
      cardTheme: CardThemeData(
        elevation: AppConstants.elevationNone,
        color: AppConstants.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
          side: const BorderSide(
            color: AppConstants.borderColor,
            width: AppConstants.borderWidthThin,
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      // Elevated Button - Primary accent
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: AppConstants.elevationNone,
          backgroundColor: AppConstants.synapseIndigo,
          foregroundColor: AppConstants.white,
          disabledBackgroundColor: AppConstants.borderColor,
          disabledForegroundColor: AppConstants.textTertiary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
            vertical: AppConstants.spacingM,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Outlined Button - Subtle border
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: AppConstants.elevationNone,
          foregroundColor: AppConstants.synapseIndigo,
          disabledForegroundColor: AppConstants.textTertiary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
            vertical: AppConstants.spacingM,
          ),
          side: const BorderSide(
            color: AppConstants.borderColor,
            width: AppConstants.borderWidthThin,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Text Button - Minimal
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppConstants.synapseIndigo,
          disabledForegroundColor: AppConstants.textTertiary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingM,
            vertical: AppConstants.spacingS,
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Input Decoration - Clean, bordered
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingM,
          vertical: AppConstants.spacingM,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.borderColor,
            width: AppConstants.borderWidthThin,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.borderColor,
            width: AppConstants.borderWidthThin,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.synapseIndigo,
            width: AppConstants.borderWidthMedium,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.errorColor,
            width: AppConstants.borderWidthThin,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.errorColor,
            width: AppConstants.borderWidthMedium,
          ),
        ),
        hintStyle: GoogleFonts.inter(
          color: AppConstants.textTertiary,
          fontSize: 15,
        ),
        labelStyle: GoogleFonts.inter(
          color: AppConstants.textSecondary,
          fontSize: 15,
        ),
        errorStyle: GoogleFonts.inter(
          color: AppConstants.errorColor,
          fontSize: 13,
        ),
        // Explicit text style for input text
        floatingLabelStyle: GoogleFonts.inter(
          color: AppConstants.synapseIndigo,
          fontSize: 15,
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: AppConstants.softWhite,
        deleteIconColor: AppConstants.textSecondary,
        disabledColor: AppConstants.dividerColor,
        selectedColor: AppConstants.synapseIndigo.withValues(alpha: 0.1),
        secondarySelectedColor: AppConstants.synapseIndigoLight.withValues(alpha: 0.1),
        labelPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingS,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingM,
          vertical: AppConstants.spacingS,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          side: const BorderSide(
            color: AppConstants.borderColor,
            width: AppConstants.borderWidthThin,
          ),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppConstants.textPrimary,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        brightness: Brightness.light,
        elevation: AppConstants.elevationNone,
        pressElevation: AppConstants.elevationNone,
      ),

      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: AppConstants.dividerColor,
        thickness: 1,
        space: 1,
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppConstants.white,
        elevation: AppConstants.elevationLow,
        selectedItemColor: AppConstants.synapseIndigo,
        unselectedItemColor: AppConstants.textSecondary,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: AppConstants.elevationMedium,
        backgroundColor: AppConstants.synapseIndigo,
        foregroundColor: AppConstants.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        ),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        elevation: AppConstants.elevationMedium,
        backgroundColor: AppConstants.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          side: const BorderSide(
            color: AppConstants.borderColor,
            width: AppConstants.borderWidthThin,
          ),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppConstants.textPrimary,
          letterSpacing: -0.5,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 15,
          color: AppConstants.textSecondary,
          height: 1.5,
        ),
      ),

      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppConstants.deepSpace,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.starlight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: AppConstants.elevationMedium,
      ),

      // Typography - Inter for maximum readability
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          fontSize: 57,
          fontWeight: FontWeight.w700,
          color: AppConstants.textPrimary,
          letterSpacing: -1.5,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 45,
          fontWeight: FontWeight.w700,
          color: AppConstants.textPrimary,
          letterSpacing: -1.0,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: AppConstants.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: -0.3,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: -0.5,
          height: 1.2,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: -0.2,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: -0.1,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppConstants.textPrimary,
          letterSpacing: -0.1,
          height: 1.6,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppConstants.textPrimary,
          letterSpacing: 0,
          height: 1.5,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppConstants.textSecondary,
          letterSpacing: 0,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: 0,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppConstants.textPrimary,
          letterSpacing: 0,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppConstants.textSecondary,
          letterSpacing: 0,
        ),
      ),

      // Icon Theme - Line-Art Icons (weight 1.5)
      iconTheme: const IconThemeData(
        color: AppConstants.textPrimary,
        size: 24,
        weight: 300, // Light weight for line-art style
        opticalSize: 24,
        fill: 0.0, // Outlined style
      ),

      // Progress Indicator Theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppConstants.synapseIndigo,
      ),
    );
  }

  /// Dark Theme - Premium Dark Mode (Mockup Design)
  static ThemeData get darkTheme {

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Color Scheme - Dark Mode from Mockup
      colorScheme: ColorScheme.dark(
        primary: AppConstants.primaryBlueCyan,  // #13A4EC from mockup
        onPrimary: AppConstants.white,
        primaryContainer: AppConstants.primaryBlueCyan.withValues(alpha: 0.2),
        onPrimaryContainer: AppConstants.starlight,

        secondary: AppConstants.recallCyan,
        onSecondary: AppConstants.backgroundDark,

        tertiary: AppConstants.synapseIndigoLight,
        onTertiary: AppConstants.backgroundDark,

        error: AppConstants.errorColor,
        onError: AppConstants.white,

        surface: AppConstants.surfaceDark, // #1C2327 from mockup
        onSurface: AppConstants.starlight,
        surfaceContainerHighest: Color(0xFF2A3338), // Slightly lighter for elevated surfaces

        outline: Color(0xFF3A4449), // Subtle border in dark mode
        outlineVariant: Color(0xFF2A3338),
      ),

      // Scaffold - Background Dark from mockup
      scaffoldBackgroundColor: AppConstants.backgroundDark, // #101C22 from mockup

      // App Bar Theme
      appBarTheme: AppBarTheme(
        elevation: AppConstants.elevationNone,
        backgroundColor: AppConstants.backgroundDark,
        foregroundColor: AppConstants.starlight,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(
          color: AppConstants.starlight,
          size: 24,
          weight: 300,
          opticalSize: 24,
          fill: 0.0,
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        elevation: AppConstants.elevationNone,
        color: AppConstants.surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL), // Larger radius like mockup
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: AppConstants.borderWidthThin,
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: AppConstants.elevationNone,
          backgroundColor: AppConstants.primaryBlueCyan,
          foregroundColor: AppConstants.white,
          disabledBackgroundColor: Color(0xFF3A4449),
          disabledForegroundColor: AppConstants.slateGray,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
            vertical: AppConstants.spacingM,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Outlined Button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: AppConstants.elevationNone,
          foregroundColor: AppConstants.synapseIndigoLight,
          disabledForegroundColor: AppConstants.slateGray,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
            vertical: AppConstants.spacingM,
          ),
          side: const BorderSide(
            color: Color(0xFF475569),
            width: AppConstants.borderWidthThin,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppConstants.synapseIndigoLight,
          disabledForegroundColor: AppConstants.slateGray,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingM,
            vertical: AppConstants.spacingS,
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingM,
          vertical: AppConstants.spacingM,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: AppConstants.borderWidthThin,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: AppConstants.borderWidthThin,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.primaryBlueCyan,
            width: AppConstants.borderWidthMedium,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.errorColor,
            width: AppConstants.borderWidthThin,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          borderSide: const BorderSide(
            color: AppConstants.errorColor,
            width: AppConstants.borderWidthMedium,
          ),
        ),
        hintStyle: GoogleFonts.inter(
          color: AppConstants.slateGray,
          fontSize: 15,
        ),
        labelStyle: GoogleFonts.inter(
          color: AppConstants.slateGray,
          fontSize: 15,
        ),
        errorStyle: GoogleFonts.inter(
          color: AppConstants.errorColor,
          fontSize: 13,
        ),
        // Explicit text style for input text
        floatingLabelStyle: GoogleFonts.inter(
          color: AppConstants.primaryBlueCyan,
          fontSize: 15,
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: Color(0xFF1E293B),
        deleteIconColor: AppConstants.slateGray,
        disabledColor: Color(0xFF334155),
        selectedColor: AppConstants.synapseIndigo.withValues(alpha: 0.2),
        secondarySelectedColor: AppConstants.synapseIndigoLight.withValues(alpha: 0.2),
        labelPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingS,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingM,
          vertical: AppConstants.spacingS,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          side: const BorderSide(
            color: Color(0xFF475569),
            width: AppConstants.borderWidthThin,
          ),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppConstants.starlight,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        brightness: Brightness.dark,
        elevation: AppConstants.elevationNone,
        pressElevation: AppConstants.elevationNone,
      ),

      // Divider Theme
      dividerTheme: const DividerThemeData(
        color: Color(0xFF334155),
        thickness: 1,
        space: 1,
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppConstants.surfaceDark,
        elevation: 0,
        selectedItemColor: AppConstants.primaryBlueCyan,
        unselectedItemColor: AppConstants.slateGray,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 8,
        backgroundColor: AppConstants.primaryBlueCyan,
        foregroundColor: AppConstants.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        ),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        elevation: AppConstants.elevationMedium,
        backgroundColor: Color(0xFF1E293B),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          side: const BorderSide(
            color: Color(0xFF475569),
            width: AppConstants.borderWidthThin,
          ),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppConstants.starlight,
          letterSpacing: -0.5,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 15,
          color: AppConstants.slateGray,
          height: 1.5,
        ),
      ),

      // Snackbar Theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Color(0xFF1E293B),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppConstants.starlight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: AppConstants.elevationMedium,
      ),

      // Typography
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          fontSize: 57,
          fontWeight: FontWeight.w700,
          color: AppConstants.starlight,
          letterSpacing: -1.5,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 45,
          fontWeight: FontWeight.w700,
          color: AppConstants.starlight,
          letterSpacing: -1.0,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: AppConstants.starlight,
          letterSpacing: -0.5,
        ),
        headlineLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: -0.5,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: -0.5,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: -0.3,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: -0.3,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: -0.2,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: -0.1,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppConstants.starlight,
          letterSpacing: 0,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppConstants.starlight,
          letterSpacing: 0,
          height: 1.5,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppConstants.slateGray,
          letterSpacing: 0,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: 0,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppConstants.starlight,
          letterSpacing: 0,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppConstants.slateGray,
          letterSpacing: 0,
        ),
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: AppConstants.starlight,
        size: 24,
        weight: 300,
        opticalSize: 24,
        fill: 0.0,
      ),

      // Progress Indicator Theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppConstants.synapseIndigo,
      ),
    );
  }
}
