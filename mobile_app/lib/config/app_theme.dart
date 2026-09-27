import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_constants.dart';

class AppTheme {
  static TextTheme _buildTextTheme(bool dark) {
    final base = dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final fg   = dark ? AppColors.textPrimary   : const Color(0xFF0F172A);
    final fg2  = dark ? AppColors.textSecondary : const Color(0xFF475569);
    final fg3  = dark ? AppColors.textMuted     : const Color(0xFF64748B);
    return GoogleFonts.interTextTheme(base).copyWith(
      displayLarge:   GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: fg, letterSpacing: -1.0),
      displayMedium:  GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.8),
      displaySmall:   GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.5),
      headlineLarge:  GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.3),
      headlineMedium: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.2),
      headlineSmall:  GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
      titleLarge:     GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: fg),
      titleMedium:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: fg),
      titleSmall:     GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: fg),
      bodyLarge:      GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w400, color: fg),
      bodyMedium:     GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: fg2),
      bodySmall:      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: fg3),
      labelLarge:     GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: fg, letterSpacing: 0.1),
      labelMedium:    GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: fg2, letterSpacing: 0.1),
      labelSmall:     GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: fg3, letterSpacing: 0.2),
    );
  }

  static ThemeData get darkTheme  => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg     = isDark ? AppColors.background   : const Color(0xFFF8FAFC);
    final srf    = isDark ? AppColors.surface       : Colors.white;
    final border = isDark ? AppColors.borderSubtle  : const Color(0xFFE2E8F0);
    final onSurf = isDark ? AppColors.textPrimary   : const Color(0xFF0F172A);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: bg,

      colorScheme: ColorScheme(
        brightness: brightness,
        primary:    AppColors.primary,
        onPrimary:  Colors.white,
        primaryContainer: AppColors.primaryGlow,
        onPrimaryContainer: AppColors.primary,
        secondary:  AppColors.accentIndigo,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFF1E2040),
        onSecondaryContainer: AppColors.accentIndigo,
        error:      AppColors.error,
        onError:    Colors.white,
        errorContainer: AppColors.errorGlow,
        onErrorContainer: AppColors.error,
        surface:    srf,
        onSurface:  onSurf,
        surfaceContainerHighest: isDark ? AppColors.surface2 : const Color(0xFFF1F5F9),
        outline:    border,
        outlineVariant: isDark ? AppColors.borderDefault : const Color(0xFFCBD5E1),
      ),

      textTheme: _buildTextTheme(isDark),

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: bg,
        foregroundColor: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusMedium),
          side: BorderSide(color: border),
        ),
        color: srf,
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? AppColors.textPrimary : const Color(0xFF0F172A),
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surface2 : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(fontSize: 14,
            color: isDark ? AppColors.textSecondary : const Color(0xFF64748B)),
        hintStyle: GoogleFonts.inter(fontSize: 14,
            color: isDark ? AppColors.textMuted : const Color(0xFF94A3B8)),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: isDark ? AppColors.surface3 : const Color(0xFFE2E8F0),
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primaryGlow,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        trackHeight: 3,
        valueIndicatorColor: AppColors.primaryDark,
        valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
        showValueIndicator: ShowValueIndicator.onDrag,
        valueIndicatorTextStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary
                : (isDark ? AppColors.textMuted : Colors.white)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primaryGlow
                : (isDark ? AppColors.surface3 : const Color(0xFFE2E8F0))),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 0,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: isDark ? AppColors.textMuted : const Color(0xFF94A3B8),
        selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        indicatorColor: AppColors.primaryGlow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? AppColors.primary
              : (isDark ? AppColors.textMuted : const Color(0xFF94A3B8)),
          size: 22,
        )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.inter(
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? AppColors.primary
              : (isDark ? AppColors.textMuted : const Color(0xFF94A3B8)),
        )),
        elevation: 0,
        height: 68,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.surface2 : const Color(0xFFF1F5F9),
        selectedColor: AppColors.primaryGlow,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
            fontSize: 18, fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimary : const Color(0xFF0F172A)),
        contentTextStyle: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? AppColors.textSecondary : const Color(0xFF475569)),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surface2 : const Color(0xFF0F172A),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
    );
  }
}
