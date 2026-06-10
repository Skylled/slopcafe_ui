import 'package:flutter/material.dart';
import 'design/tokens.dart';
import 'design/typography.dart';

/// Assembles the Cortado [ThemeData] (light + dark) from the design tokens.
///
/// The [AppColors] token set is registered as a [ThemeExtension] so bespoke
/// widgets can read raw tokens via `context.colors`, while the standard Material
/// [ColorScheme] is mapped onto the same palette so existing `Theme.of(context)`
/// references keep resolving to sensible Cortado colours.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _build(Brightness.light, AppColors.light);
  static ThemeData get darkTheme => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.clay,
      onPrimary: c.onAccent,
      primaryContainer: c.claySoft,
      onPrimaryContainer: c.clayD,
      secondary: c.honey,
      onSecondary: c.onAccent,
      secondaryContainer: Color.alphaBlend(
        c.honey.withValues(alpha: 0.18),
        c.surface,
      ),
      onSecondaryContainer: c.honeyD,
      tertiary: c.honeyD,
      onTertiary: c.onAccent,
      error: c.red,
      onError: c.onAccent,
      errorContainer: Color.alphaBlend(
        c.red.withValues(alpha: 0.12),
        c.surface,
      ),
      onErrorContainer: c.red,
      surface: c.surface,
      onSurface: c.text,
      surfaceContainerLowest: c.bgDeep,
      surfaceContainerLow: c.bg,
      surfaceContainer: c.surface2,
      surfaceContainerHigh: c.surface2,
      surfaceContainerHighest: c.surface3,
      onSurfaceVariant: c.textDim,
      outline: c.line,
      outlineVariant: c.lineSoft,
      shadow: const Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      colorScheme: scheme,
      extensions: [c],
      textTheme: AppText.textTheme(c.text),
      fontFamilyFallback: const ['SF Pro Text', 'Roboto'],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: c.text,
        titleTextStyle: AppText.headline.copyWith(color: c.text),
        iconTheme: IconThemeData(color: c.text),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          side: BorderSide(color: c.lineSoft),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.lineSoft, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.textDim),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface2,
        hintStyle: AppText.body.copyWith(color: c.textFaint),
        labelStyle: AppText.body.copyWith(color: c.textDim),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.clay, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: c.red, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.clay,
          foregroundColor: c.onAccent,
          minimumSize: const Size(0, 50),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: AppText.title.copyWith(fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: c.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: AppText.title.copyWith(fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.clayD,
          textStyle: AppText.title.copyWith(fontSize: 14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface3,
        contentTextStyle: AppText.body.copyWith(color: c.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: c.line),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.clay,
        linearTrackColor: c.surface3,
        circularTrackColor: c.surface3,
      ),
    );
  }
}
