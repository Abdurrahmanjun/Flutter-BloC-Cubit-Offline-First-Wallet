import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens that don't fit into Material's [ColorScheme] — the accent
/// gradient, surface-alt, hairline borders, muted/faint text, success/danger,
/// and the shared radius scale. Pulled from the design handoff.
///
/// Access from any widget with `Theme.of(context).extension<WalletTokens>()!`
/// or the `context.tokens` helper below.
@immutable
class WalletTokens extends ThemeExtension<WalletTokens> {
  const WalletTokens({
    required this.screenBackground,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.hairline,
    required this.success,
    required this.danger,
    required this.accentStart,
    required this.accentEnd,
  });

  final Color screenBackground;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;
  final Color hairline;
  final Color success;
  final Color danger;

  /// Two-stop accent gradient (same in both themes).
  final Color accentStart;
  final Color accentEnd;

  /// Accent gradient at 140deg — used on the mark, balance card, primary
  /// buttons, and active icons.
  LinearGradient get accentGradient => LinearGradient(
        colors: [accentStart, accentEnd],
        // 140deg: begin top-ish-left, end bottom-ish-right.
        begin: const Alignment(-0.64, -1),
        end: const Alignment(0.64, 1),
      );

  /// ~12% opacity accent tint used behind soft-accent icons/badges.
  Color get accentSoft => Color.alphaBlend(
        accentStart.withValues(alpha: 0.12),
        surface,
      );

  /// The mid accent, handy for single-color icons/text on soft fills.
  Color get accent => Color.lerp(accentStart, accentEnd, 0.5)!;

  // Radius scale from the handoff.
  static const double rBalanceCard = 26;
  static const double rAppMark = 28;
  static const double rActionTile = 18;
  static const double rInput = 16;
  static const double rIconButton = 13;
  static const double rAvatar = 14;
  static const double rPill = 20;

  @override
  WalletTokens copyWith({
    Color? screenBackground,
    Color? surface,
    Color? surfaceAlt,
    Color? textPrimary,
    Color? textMuted,
    Color? textFaint,
    Color? hairline,
    Color? success,
    Color? danger,
    Color? accentStart,
    Color? accentEnd,
  }) {
    return WalletTokens(
      screenBackground: screenBackground ?? this.screenBackground,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      hairline: hairline ?? this.hairline,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      accentStart: accentStart ?? this.accentStart,
      accentEnd: accentEnd ?? this.accentEnd,
    );
  }

  @override
  WalletTokens lerp(ThemeExtension<WalletTokens>? other, double t) {
    if (other is! WalletTokens) return this;
    return WalletTokens(
      screenBackground:
          Color.lerp(screenBackground, other.screenBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      accentStart: Color.lerp(accentStart, other.accentStart, t)!,
      accentEnd: Color.lerp(accentEnd, other.accentEnd, t)!,
    );
  }

  static const light = WalletTokens(
    screenBackground: Color(0xFFEEF1F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF5F7FC),
    textPrimary: Color(0xFF0F1729),
    textMuted: Color(0xFF606B82),
    textFaint: Color(0xFF9AA3B5),
    hairline: Color(0x170F1729), // rgba(15,23,41,0.09)
    success: Color(0xFF1FA971),
    danger: Color(0xFFE5484D),
    accentStart: Color(0xFF3D6FF5),
    accentEnd: Color(0xFF6A5CFF),
  );

  static const dark = WalletTokens(
    screenBackground: Color(0xFF0B0E14),
    surface: Color(0xFF151A22),
    surfaceAlt: Color(0xFF1B2029),
    textPrimary: Color(0xFFEAEEF6),
    textMuted: Color(0xFF98A2B6),
    textFaint: Color(0x66667084), // rgba(102,112,132,0.4)
    hairline: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    success: Color(0xFF37D399),
    danger: Color(0xFFFF6B6E),
    accentStart: Color(0xFF3D6FF5),
    accentEnd: Color(0xFF6A5CFF),
  );
}

/// Convenience accessor for [WalletTokens] and numeric-font styles.
extension WalletThemeX on BuildContext {
  WalletTokens get tokens => Theme.of(this).extension<WalletTokens>()!;

  /// Space Grotesk — the numeric/display font (balance, amounts, tx values).
  TextStyle numeric({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w700,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: color ?? tokens.textPrimary,
      );
}

class AppTheme {
  static ThemeData get light => _build(WalletTokens.light, Brightness.light);
  static ThemeData get dark => _build(WalletTokens.dark, Brightness.dark);

  static ThemeData _build(WalletTokens t, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: t.accentStart,
      brightness: brightness,
    ).copyWith(
      surface: t.surface,
      primary: t.accentStart,
      error: t.danger,
    );

    // Manrope is the UI font; apply token colors over the Google Fonts theme.
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: t.textPrimary,
      displayColor: t.textPrimary,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: t.screenBackground,
      textTheme: textTheme,
      extensions: [t],
      // Drive Flutter routes with the Android 14+ predictive-back animation, so
      // the system back-swipe peeks the previous screen (needs the
      // enableOnBackInvokedCallback flag in AndroidManifest.xml).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.screenBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: t.textPrimary,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: t.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}
