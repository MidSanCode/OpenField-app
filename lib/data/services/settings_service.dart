import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists app-level preferences: language and color theme.
class SettingsService extends ChangeNotifier {
  static const _keyLocale = 'settings_locale';
  static const _keyThemeMode = 'settings_theme_mode';

  String? _locale;
  ThemeMode _themeMode = ThemeMode.system;

  String? get locale => _locale;
  ThemeMode get themeMode => _themeMode;

  SettingsService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = prefs.getString(_keyLocale);
    final themeName = prefs.getString(_keyThemeMode);
    _themeMode = _themeNameToMode(themeName);
    notifyListeners();
  }

  Future<void> setLocale(String? locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_keyLocale);
    } else {
      await prefs.setString(_keyLocale, locale);
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, _modeToName(mode));
    notifyListeners();
  }

  ThemeMode _themeNameToMode(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _modeToName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
