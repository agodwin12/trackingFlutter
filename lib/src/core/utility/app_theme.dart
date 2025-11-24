// lib/core/utils/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ========== PROXYM MOBILITY BRAND COLORS (From Charte Graphique) ==========

  /// JAUNE AMBRE (Primary Brand Color)
  /// HEX: #f8c812 | RVB: 248-200-18 | CMJN: 3-20-99-0
  static const Color primary = Color(0xFFD85119);

  /// NOIR (Brand Black)
  /// HEX: #1d1d1b | RVB: 29-29-27 | CMJN: 71-65-67-77
  static const Color black = Color(0xFF1D1D1B);

  /// White
  static const Color white = Color(0xFFFFFFFF);

  // ========== ADDITIONAL UI COLORS ==========

  /// Light background
  static const Color background = Color(0xFFF8F9FA);

  /// Gray text (for secondary information)
  static const Color textSecondary = Color(0xFF9EA2AD);

  /// Light gray (for borders and dividers)
  static const Color border = Color(0xFFE9EAEB);

  /// Success green
  static const Color success = Color(0xFF4CAF50);

  /// Error red
  static const Color error = Color(0xFFF44336);

  /// Warning orange
  static const Color warning = Color(0xFFFF9800);

  /// Info blue
  static const Color info = Color(0xFF2196F3);

  static const Color cardBackground = Color(0xFFF5F5F5); // Light gray
  // ========== OPACITY VARIANTS ==========

  static Color primaryLight = primary.withOpacity(0.1);
  static Color primaryMedium = primary.withOpacity(0.5);
  static Color blackLight = black.withOpacity(0.1);
  static Color blackMedium = black.withOpacity(0.5);
}

class AppTypography {
  // ========== PROXYM MOBILITY FONTS (From Charte Graphique) ==========

  /// Primary Font: TESLA (for large titles only)
  /// Note: You need to add TESLA font to your project
  /// For now, using Poppins as fallback with similar weight
  static TextStyle tesla({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w800,
    Color color = AppColors.black,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing ?? 1.2,
    );
  }

  /// Secondary Font: Metropolis (for subtitles and paragraphs)
  /// Note: Using Poppins as Metropolis is similar
  static TextStyle metropolis({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.black,
    double? height,
  }) {
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  // ========== COMMON TEXT STYLES ==========

  /// Large title (using TESLA style)
  static TextStyle get h1 => tesla(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.black,
  );

  /// Medium title (using TESLA style)
  static TextStyle get h2 => tesla(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.black,
  );

  /// Small title (using TESLA style)
  static TextStyle get h3 => tesla(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.black,
  );

  /// Section header (using Metropolis style)
  static TextStyle get subtitle1 => metropolis(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.black,
  );

  /// Subsection header (using Metropolis style)
  static TextStyle get subtitle2 => metropolis(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.black,
  );

  /// Body text (using Metropolis style)
  static TextStyle get body1 => metropolis(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.black,
  );

  /// Secondary body text (using Metropolis style)
  static TextStyle get body2 => metropolis(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Small text (using Metropolis style)
  static TextStyle get caption => metropolis(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Button text (using Metropolis style)
  static TextStyle get button => metropolis(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.white,
  );
}

class AppSizes {
  // ========== SPACING ==========
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;

  // ========== BORDER RADIUS ==========
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;

  // ========== ICON SIZES ==========
  static const double iconS = 16.0;
  static const double iconM = 24.0;
  static const double iconL = 32.0;
  static const double iconXL = 48.0;
}