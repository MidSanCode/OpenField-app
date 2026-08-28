import 'package:flutter/material.dart';

class AppTheme {
  static const Color seed = Color(0xFF4CAF50);

  /// Font family used as the application-wide typeface. Chiron GoRound TC is
  /// a friendly handwritten font; the static OTF files (regular and bold) are
  /// bundled in assets/fonts and registered via pubspec.yaml, so the font is
  /// always available offline and never depends on a network round-trip.
  static const String _fontFamily = 'Chiron GoRound TC';

  /// Fallback chain for glyphs that Chiron does not cover (CJK characters,
  /// emoji, etc.). Flutter picks the first family that has a glyph, so Latin
  /// text uses Chiron and Chinese text falls back to the platform default
  /// without throwing "no font family" errors.
  static const List<String> _fontFallback = <String>[
    'Roboto',
    'Noto Sans',
    'Noto Sans CJK SC',
    'Noto Sans CJK',
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'Source Han Sans SC',
    'Source Han Sans CN',
    'sans-serif',
  ];

  /// Builds a card theme from a fill color. The fill is the M3 card surface
  /// (surfaceContainerLow) already tinted by [cardOpacity] so the rounded panel
  /// stays a floating solid-looking card at opacity 1.0 and becomes
  /// progressively see-through below it.
  static CardThemeData _cardThemeOf(Color fill) => CardThemeData(
        elevation: 1,
        shadowColor: Colors.black26,
        clipBehavior: Clip.antiAlias,
        color: fill,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      );

  /// The application-wide font. Chiron GoRound TC is a friendly handwritten
  /// typeface bundled as assets/fonts/ChironGoRoundTC-{400R,700B}.otf; it
  /// only carries Latin/Greek/Vietnamese glyphs so the fallback chain renders
  /// CJK characters via the platform default.
  static TextTheme _textTheme(Color onSurface) {
    final base = ThemeData(brightness: Brightness.light).textTheme;
    TextStyle withFont(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          color: onSurface,
        );
    return base.copyWith(
      displayLarge: withFont(base.displayLarge),
      displayMedium: withFont(base.displayMedium),
      displaySmall: withFont(base.displaySmall),
      headlineLarge: withFont(base.headlineLarge),
      headlineMedium: withFont(base.headlineMedium),
      headlineSmall: withFont(base.headlineSmall),
      titleLarge: withFont(base.titleLarge),
      titleMedium: withFont(base.titleMedium),
      titleSmall: withFont(base.titleSmall),
      bodyLarge: withFont(base.bodyLarge),
      bodyMedium: withFont(base.bodyMedium),
      bodySmall: withFont(base.bodySmall),
      labelLarge: withFont(base.labelLarge),
      labelMedium: withFont(base.labelMedium),
      labelSmall: withFont(base.labelSmall),
    );
  }

  /// Builds a theme from a user-chosen seed color, falling back to [seed].
  static ThemeData light(Color? seedColor, {double cardOpacity = 1.0}) {
    final s = seedColor ?? seed;
    final scheme = ColorScheme.fromSeed(seedColor: s, brightness: Brightness.light);
    final card = scheme.surfaceContainerLow.withValues(alpha: cardOpacity.clamp(0.0, 1.0));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: _cardThemeOf(card),
      textTheme: _textTheme(scheme.onSurface),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  static ThemeData dark(Color? seedColor, {double cardOpacity = 1.0}) {
    final s = seedColor ?? seed;
    final scheme = ColorScheme.fromSeed(seedColor: s, brightness: Brightness.dark);
    final card = scheme.surfaceContainerLow.withValues(alpha: cardOpacity.clamp(0.0, 1.0));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: _cardThemeOf(card),
      textTheme: _textTheme(scheme.onSurface),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}