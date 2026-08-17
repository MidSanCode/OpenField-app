import 'package:flutter/material.dart';

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      );

  /// Builds a theme from a user-chosen seed color, falling back to [seed].
  static ThemeData light(Color? seedColor, {double cardOpacity = 1.0}) {
    final s = seedColor ?? seed;
    final scheme = ColorScheme.fromSeed(seedColor: s, brightness: Brightness.light);
    final card = scheme.surfaceContainerLow.withValues(alpha: cardOpacity.clamp(0.0, 1.0));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: _cardThemeOf(card),
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
