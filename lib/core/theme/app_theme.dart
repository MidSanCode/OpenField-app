import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color seed = Color(0xFF4CAF50);

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
  /// font that mixes Chinese, Latin and digits; google_fonts loads it on first
  /// use and caches the binary locally so subsequent launches are instant and
  /// work offline once the cache has been primed.
  static TextTheme _textTheme(Color onSurface) {
    // Build each text-theme slot from the Chiron GoRound TC family so the
    // font covers every scale. google_fonts loads the binary lazily on first
    // paint and falls back to the platform default until then. We use the
    // dynamic getFont API so the code does not depend on generated static
    // methods whose name may vary between google_fonts versions.
    final base = ThemeData(brightness: Brightness.light).textTheme;
    TextStyle withFont(TextStyle? s) => GoogleFonts.getFont(
            'Chiron GoRound TC',
            textStyle: s ?? const TextStyle())
        .copyWith(color: onSurface);
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