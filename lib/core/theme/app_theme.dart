import 'package:flutter/material.dart';

class AppTheme {
  static const Color seed = Color(0xFF4CAF50);

  /// Builds a theme from a user-chosen seed color, falling back to [seed].
  static ThemeData light(Color? seedColor) {
    final s = seedColor ?? seed;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: s, brightness: Brightness.light),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  static ThemeData dark(Color? seedColor) {
    final s = seedColor ?? seed;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: s, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }
}
