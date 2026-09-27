import 'package:flutter/material.dart';

class AppColors {
  // ── Base surfaces
  static const Color background    = Color(0xFF080D1A);
  static const Color surface       = Color(0xFF0F1629);
  static const Color surface2      = Color(0xFF162040);
  static const Color surface3      = Color(0xFF1C2A50);
  static const Color borderSubtle  = Color(0xFF1E2D4A);
  static const Color borderDefault = Color(0xFF243558);

  // ── Primary accent – Amber/Gold (one accent, used consistently)
  static const Color primary       = Color(0xFFF59E0B);
  static const Color primaryLight  = Color(0xFFFCD34D);
  static const Color primaryDark   = Color(0xFFD97706);
  static const Color primaryGlow   = Color(0x33F59E0B);

  // ── Status colors
  static const Color success       = Color(0xFF10B981);
  static const Color successGlow   = Color(0x2210B981);
  static const Color error         = Color(0xFFEF4444);
  static const Color errorGlow     = Color(0x22EF4444);
  static const Color warning       = Color(0xFFF59E0B);

  // ── Feature accent colors (muted, professional)
  static const Color accentIndigo  = Color(0xFF6366F1);
  static const Color accentEmerald = Color(0xFF059669);
  static const Color accentViolet  = Color(0xFF7C3AED);
  static const Color accentRose    = Color(0xFFE11D48);
  static const Color accentCyan    = Color(0xFF0891B2);

  // ── Text
  static const Color textPrimary   = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted     = Color(0xFF475569);
  static const Color textDisabled  = Color(0xFF334155);

  // ── Backward compatibility aliases
  static const Color backgroundDark     = background;
  static const Color backgroundLight    = Color(0xFFF1F5F9);
  static const Color cardDark           = surface;
  static const Color cardLight          = Color(0xFFFFFFFF);
  static const Color textPrimaryDark    = textPrimary;
  static const Color textSecondaryDark  = textSecondary;
  static const Color dividerDark        = borderSubtle;
  static const Color dividerLight       = Color(0xFFE2E8F0);
  static const Color primaryColor       = primary;
  static const Color accentColor        = accentIndigo;
  static const Color successColor       = success;
  static const Color warningColor       = warning;
  static const Color errorColor         = error;
  static const Color glassmorphismBg    = Color(0x28FFFFFF);
  static const Color glassmorphismBgDark = Color(0x18FFFFFF);
  static const Color primaryGradientStart = primary;
  static const Color primaryGradientEnd   = primaryDark;
  static const Color ttsGradientStart     = accentViolet;
  static const Color ttsGradientEnd       = Color(0xFF6D28D9);
  static const Color ocrGradientStart     = accentRose;
  static const Color ocrGradientEnd       = Color(0xFFBE123C);

  // ── Gradients
  static LinearGradient get primaryGradient => const LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get heroGradient => const LinearGradient(
    colors: [Color(0xFF0F1629), Color(0xFF162040)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get indigoGradient => const LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get emeraldGradient => const LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get violetGradient => const LinearGradient(
    colors: [Color(0xFF6D28D9), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Backward compat gradient aliases
  static LinearGradient get accentGradient  => indigoGradient;
  static LinearGradient get successGradient => emeraldGradient;
  static LinearGradient get warningGradient => primaryGradient;
  static LinearGradient get ttsGradient     => violetGradient;
  static LinearGradient get ocrGradient     => const LinearGradient(
    colors: [Color(0xFFE11D48), Color(0xFFBE123C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
