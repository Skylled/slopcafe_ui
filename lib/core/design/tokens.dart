import 'package:flutter/material.dart';

/// Cortado design-system tokens.
///
/// The palette originates from the Claude Design "Cortado-light" mockup, authored
/// in OKLCH. Those OKLCH values were converted to sRGB (see plan) and frozen as
/// the constants below. A matching espresso-based "Cortado-dark" set keeps system
/// dark mode working.
///
/// Tokens are exposed as a [ThemeExtension] so they switch automatically with
/// the active [ThemeData]. Read them anywhere via `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.bgDeep,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineSoft,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.clay,
    required this.clayD,
    required this.claySoft,
    required this.honey,
    required this.honeyD,
    required this.green,
    required this.red,
    required this.onAccent,
    required this.shadow,
    required this.shadowLg,
    required this.glow,
  });

  final Color bg;
  final Color bgDeep;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color lineSoft;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color clay;
  final Color clayD;
  final Color claySoft;
  final Color honey;
  final Color honeyD;
  final Color green;
  final Color red;
  final Color onAccent;
  final List<BoxShadow> shadow;
  final List<BoxShadow> shadowLg;
  final List<BoxShadow> glow;

  // ---- Cortado-light (OKLCH -> sRGB, verified) ----
  static final AppColors light = AppColors(
    bg: const Color(0xFFF9F5F0),
    bgDeep: const Color(0xFFF2EEE8),
    surface: const Color(0xFFFFFFFF),
    surface2: const Color(0xFFF6F3EE),
    surface3: const Color(0xFFECE7E1),
    line: const Color(0xFFE1DDD8),
    lineSoft: const Color(0xFFECE9E5),
    text: const Color(0xFF32261F),
    textDim: const Color(0xFF6D6158),
    textFaint: const Color(0xFF918780),
    clay: const Color(0xFFB85A34),
    clayD: const Color(0xFFA24019),
    claySoft: const Color(0xFFFFE0CE),
    honey: const Color(0xFFDEA559),
    honeyD: const Color(0xFFB8752C),
    green: const Color(0xFF4E9162),
    red: const Color(0xFFC6413D),
    onAccent: const Color(0xFFFDFBF9),
    shadow: const [
      BoxShadow(color: Color(0x0D322314), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x14322314),
        blurRadius: 26,
        spreadRadius: -14,
        offset: Offset(0, 10),
      ),
    ],
    shadowLg: const [
      BoxShadow(color: Color(0x12322314), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x21322314),
        blurRadius: 60,
        spreadRadius: -22,
        offset: Offset(0, 30),
      ),
    ],
    glow: const [
      BoxShadow(
        color: Color(0x40B85A34),
        blurRadius: 40,
        spreadRadius: -18,
        offset: Offset(0, 16),
      ),
    ],
  );

  // ---- Cortado-dark (espresso base, brightened accents) ----
  static final AppColors dark = AppColors(
    bg: const Color(0xFF16100C),
    bgDeep: const Color(0xFF0F0A06),
    surface: const Color(0xFF211A15),
    surface2: const Color(0xFF2B241E),
    surface3: const Color(0xFF39312B),
    line: const Color(0xFF3E3631),
    lineSoft: const Color(0xFF302A25),
    text: const Color(0xFFEDE7DF),
    textDim: const Color(0xFFB5ACA4),
    textFaint: const Color(0xFF887E77),
    clay: const Color(0xFFDA7B55),
    clayD: const Color(0xFFCB6440),
    claySoft: const Color(0xFF4F2B1A),
    honey: const Color(0xFFEBB25F),
    honeyD: const Color(0xFFD6954A),
    green: const Color(0xFF66B27C),
    red: const Color(0xFFE85852),
    onAccent: const Color(0xFF110C09),
    shadow: const [
      BoxShadow(color: Color(0x40000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x59000000),
        blurRadius: 26,
        spreadRadius: -14,
        offset: Offset(0, 10),
      ),
    ],
    shadowLg: const [
      BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x80000000),
        blurRadius: 60,
        spreadRadius: -22,
        offset: Offset(0, 30),
      ),
    ],
    glow: const [
      BoxShadow(
        color: Color(0x4DDA7B55),
        blurRadius: 40,
        spreadRadius: -18,
        offset: Offset(0, 16),
      ),
    ],
  );

  /// Soft cover tint for a document, keyed by its first tag (matches the
  /// mockup's `TINTS`). Returns `(background, foreground)`.
  (Color, Color) tagTint(String? tag) {
    Color over(Color accent, double pct) =>
        Color.alphaBlend(accent.withValues(alpha: pct), surface);
    switch (tag) {
      case 'reference':
        return (over(clay, 0.16), clayD);
      case 'guide':
        return (over(honey, 0.22), honeyD);
      case 'api':
        return (over(green, 0.16), green);
      case 'recipe':
        return (over(honey, 0.26), honeyD);
      case 'changelog':
        return (over(clay, 0.13), clayD);
      case 'incident':
        return (over(red, 0.13), red);
      case 'spec':
      case 'notes':
      default:
        return (surface2, textDim);
    }
  }

  /// Deterministic decorative accent for an entity that has no tag (e.g. an
  /// agent), derived from a stable hash of its id. Decorative only — never
  /// surfaced as data.
  Color accentForId(String id) {
    final palette = [clay, honey, green, clayD, honeyD];
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }

  @override
  AppColors copyWith({
    Color? bg,
    Color? bgDeep,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? line,
    Color? lineSoft,
    Color? text,
    Color? textDim,
    Color? textFaint,
    Color? clay,
    Color? clayD,
    Color? claySoft,
    Color? honey,
    Color? honeyD,
    Color? green,
    Color? red,
    Color? onAccent,
    List<BoxShadow>? shadow,
    List<BoxShadow>? shadowLg,
    List<BoxShadow>? glow,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      bgDeep: bgDeep ?? this.bgDeep,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      text: text ?? this.text,
      textDim: textDim ?? this.textDim,
      textFaint: textFaint ?? this.textFaint,
      clay: clay ?? this.clay,
      clayD: clayD ?? this.clayD,
      claySoft: claySoft ?? this.claySoft,
      honey: honey ?? this.honey,
      honeyD: honeyD ?? this.honeyD,
      green: green ?? this.green,
      red: red ?? this.red,
      onAccent: onAccent ?? this.onAccent,
      shadow: shadow ?? this.shadow,
      shadowLg: shadowLg ?? this.shadowLg,
      glow: glow ?? this.glow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: c(bg, other.bg),
      bgDeep: c(bgDeep, other.bgDeep),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      surface3: c(surface3, other.surface3),
      line: c(line, other.line),
      lineSoft: c(lineSoft, other.lineSoft),
      text: c(text, other.text),
      textDim: c(textDim, other.textDim),
      textFaint: c(textFaint, other.textFaint),
      clay: c(clay, other.clay),
      clayD: c(clayD, other.clayD),
      claySoft: c(claySoft, other.claySoft),
      honey: c(honey, other.honey),
      honeyD: c(honeyD, other.honeyD),
      green: c(green, other.green),
      red: c(red, other.red),
      onAccent: c(onAccent, other.onAccent),
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? shadow,
      shadowLg: BoxShadow.lerpList(shadowLg, other.shadowLg, t) ?? shadowLg,
      glow: BoxShadow.lerpList(glow, other.glow, t) ?? glow,
    );
  }
}

/// Corner radii used across the Cortado system.
class AppRadii {
  AppRadii._();
  static const double pill = 99;
  static const double sm = 8;
  static const double md = 11;
  static const double lg = 13;
  static const double xl = 16;
  static const double xxl = 20;
  static const double card = 22;
  static const double sheet = 26;
}

/// Spacing scale (logical pixels) — mirrors the mockup's common gaps/paddings.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 18;
  static const double xxl = 22;
  static const double screenH = 18; // horizontal screen padding
  static const double topInset = 62; // header top inset
  static const double bottomInset = 112; // clears the floating tab bar
}

/// `context.colors` -> the active [AppColors] token set.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
