import 'package:flutter/material.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.accent,
    required this.accentSoft,
    required this.gold,
    required this.goldSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.halfDay,
    required this.textHigh,
    required this.textMid,
    required this.textLow,
    required this.border,
    required this.shadow,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color accent;
  final Color accentSoft;
  final Color gold;
  final Color goldSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color halfDay;
  final Color textHigh;
  final Color textMid;
  final Color textLow;
  final Color border;
  final Color shadow;

  static const light = AppPalette(
    bg: Color(0xFFF3F1EC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE7E4DC),
    accent: Color(0xFF4F7EFF),
    accentSoft: Color(0xFFDCE6FF),
    gold: Color(0xFFC6A227),
    goldSoft: Color(0xFFF3E6B8),
    success: Color(0xFF2FB56F),
    warning: Color(0xFFE8A017),
    danger: Color(0xFFE25B4C),
    halfDay: Color(0xFF7C6AF7),
    textHigh: Color(0xFF1A1A2E),
    textMid: Color(0xFF5C5C72),
    textLow: Color(0xFF8A8899),
    border: Color(0xFFC9C4B8),
    shadow: Color(0x14000000),
  );

  static const dark = AppPalette(
    bg: Color(0xFF080A10),
    surface: Color(0xFF1A1F2E),
    surfaceAlt: Color(0xFF2A3144),
    accent: Color(0xFF7AA0FF),
    accentSoft: Color(0xFF2A3A62),
    gold: Color(0xFFE4C04A),
    goldSoft: Color(0xFF3A3116),
    success: Color(0xFF3DDB8F),
    warning: Color(0xFFFFC14D),
    danger: Color(0xFFFF7A6E),
    halfDay: Color(0xFF9B8CFF),
    textHigh: Color(0xFFF6F5F0),
    textMid: Color(0xFFB4B7C8),
    textLow: Color(0xFF8E93A6),
    border: Color(0xFF4E566C),
    shadow: Color(0x99000000),
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? light;
  }

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? accent,
    Color? accentSoft,
    Color? gold,
    Color? goldSoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? halfDay,
    Color? textHigh,
    Color? textMid,
    Color? textLow,
    Color? border,
    Color? shadow,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      gold: gold ?? this.gold,
      goldSoft: goldSoft ?? this.goldSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      halfDay: halfDay ?? this.halfDay,
      textHigh: textHigh ?? this.textHigh,
      textMid: textMid ?? this.textMid,
      textLow: textLow ?? this.textLow,
      border: border ?? this.border,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldSoft: Color.lerp(goldSoft, other.goldSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      halfDay: Color.lerp(halfDay, other.halfDay, t)!,
      textHigh: Color.lerp(textHigh, other.textHigh, t)!,
      textMid: Color.lerp(textMid, other.textMid, t)!,
      textLow: Color.lerp(textLow, other.textLow, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppPalette.light);
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ).copyWith(
        surface: palette.surface,
        primary: palette.accent,
      ),
      extensions: [palette],
    );
  }
}
