import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─────────────────────────────────────────────
/// TV Design System — Single-accent, typography-led
/// ─────────────────────────────────────────────

class TVTheme {
  TVTheme._();

  // ── Surface ──────────────────────────────────
  static const Color bgDeep      = Color(0xFF000000);
  static const Color bgCard      = Color(0xFF1C1C1E);
  static const Color bgCardHover = Color(0xFF2C2C2E);
  static const Color bgOverlay   = Color(0xE5000000);
  static const Color separator   = Color(0xFF38383A);

  // ── Single primary accent ────────────────────
  static const Color accent = Color(0xFF0A84FF);

  // Functional tints (muted, for type identification only)
  static const Color tintWarm   = Color(0xFFFF6961); // news/error
  static const Color tintGreen  = Color(0xFF32D74B); // success/on
  static const Color tintOrange = Color(0xFFFF9F0A); // control
  static const Color tintYellow = Color(0xFFFFD60A); // game
  static const Color tintTeal   = Color(0xFF5AC8F5); // weather
  static const Color tintPurple = Color(0xFFA78BFA); // webapp/media

  // Backward-compat aliases
  static const Color accentPrimary   = accent;
  static const Color accentSecondary = tintGreen;
  static const Color accentWarm      = tintWarm;
  static const Color accentOrange    = tintOrange;
  static const Color accentYellow    = tintYellow;
  static const Color accentTeal      = tintTeal;
  static const Color accentPurple    = tintPurple;
  static const Color accentPink      = Color(0xFFFF375F);
  static const Color accentGreen     = tintGreen;

  // ── Text ─────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF98989F);
  static const Color textMuted     = Color(0xFF48484A);

  // ── Focus ────────────────────────────────────
  static const Color focusBorder = Color(0xFFFFFFFF);
  static const Color focusGlow   = Color(0x22FFFFFF);

  // ── Spacing (8pt grid) ───────────────────────
  static const double spacingXs = 8;
  static const double spacingSm = 16;
  static const double spacingMd = 24;
  static const double spacingLg = 40;
  static const double spacingXl = 64;

  // ── Radius ───────────────────────────────────
  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 24;

  static const double focusWidth = 1.5;

  // ── Typography ───────────────────────────────
  // Display: hero-level brand signal
  static TextStyle get displayLarge => GoogleFonts.notoSansKr(
        fontSize: 56, fontWeight: FontWeight.w700,
        color: textPrimary, height: 1.1, letterSpacing: -1,
      );

  static TextStyle get displayMedium => GoogleFonts.notoSansKr(
        fontSize: 36, fontWeight: FontWeight.w600,
        color: textPrimary, height: 1.2, letterSpacing: -0.5,
      );

  // Headline: section headers
  static TextStyle get headlineLarge => GoogleFonts.notoSansKr(
        fontSize: 28, fontWeight: FontWeight.w600,
        color: textPrimary, height: 1.3,
      );

  static TextStyle get headlineMedium => GoogleFonts.notoSansKr(
        fontSize: 24, fontWeight: FontWeight.w500,
        color: textPrimary, height: 1.35,
      );

  // Title: card titles (55인치 3m 최적화)
  static TextStyle get titleLarge => GoogleFonts.notoSansKr(
        fontSize: 24, fontWeight: FontWeight.w600,
        color: textPrimary, height: 1.4,
      );

  // Body: descriptions, chat messages
  static TextStyle get bodyLarge => GoogleFonts.notoSansKr(
        fontSize: 24, fontWeight: FontWeight.w400,
        color: textSecondary, height: 1.5,
      );

  static TextStyle get bodyMedium => GoogleFonts.notoSansKr(
        fontSize: 22, fontWeight: FontWeight.w400,
        color: textSecondary, height: 1.5,
      );

  // Label: buttons, badges
  static TextStyle get labelLarge => GoogleFonts.notoSansKr(
        fontSize: 22, fontWeight: FontWeight.w500,
        color: textPrimary, height: 1.4,
      );

  // Caption: metadata, timestamps
  static TextStyle get caption => GoogleFonts.notoSansKr(
        fontSize: 20, fontWeight: FontWeight.w400,
        color: textMuted, height: 1.4,
      );

  static ThemeData build() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: tintGreen,
        surface: bgCard,
        error: tintWarm,
      ),
      textTheme: TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        titleLarge: titleLarge,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        labelLarge: labelLarge,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E22),
        elevation: 8,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      iconTheme: const IconThemeData(color: textPrimary, size: 28),
    );
  }
}

/// Fluid Glass performance configuration
/// Day 1: BackdropFilter 블러 성능 스파이크 테스트 후 플래그 조정
/// - useAnimatedBlur: 50fps 이상 확인 시 true (카드 등장 시 animated blur)
/// - springCurvesOnly: 45fps 미달 시 true (glass 효과 제거, spring curves만)
/// - disableAllAnimations: 30fps 미달 시 true (모든 커스텀 애니메이션 비활성화)
class FluidGlassConfig {
  static bool useAnimatedBlur = false;
  static bool springCurvesOnly = false;
  static bool disableAllAnimations = false;
}

/// Glass 카드 — Fluid Glass style
/// unfocused: subtle glass, focused: white border + glow + elevated shadow
BoxDecoration glassDecoration({bool focused = false}) {
  return BoxDecoration(
    color: focused
        ? Colors.white.withOpacity(0.15)
        : Colors.white.withOpacity(0.06),
    borderRadius: BorderRadius.circular(TVTheme.radiusMd),
    border: focused
        ? Border.all(color: Colors.white.withOpacity(0.5), width: 2.0)
        : null,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(focused ? 0.5 : 0.2),
        blurRadius: focused ? 32 : 12,
        offset: Offset(0, focused ? 10 : 4),
      ),
      if (focused)
        BoxShadow(
          color: Colors.white.withOpacity(0.08),
          blurRadius: 20,
          spreadRadius: 4,
        ),
    ],
  );
}
