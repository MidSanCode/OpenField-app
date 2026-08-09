import 'dart:ui' show Color;

import 'package:flutter/material.dart' show ChangeNotifier, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists app-level preferences: language, color theme, server host, custom
/// background image and its visibility.
class SettingsService extends ChangeNotifier {
  static const _keyLocale = 'settings_locale';
  static const _keyThemeMode = 'settings_theme_mode';
  static const _keyDeveloperMode = 'settings_developer_mode';
  static const _keyServerHost = 'settings_server_host';
  static const _keyBackgroundImagePath = 'settings_background_image_path';
  static const _keyBackgroundVisible = 'settings_background_image_visible';
  static const _keyAccentColor = 'settings_accent_color';
  static const String defaultServerHost = 'https://of-api.msc-studio.eu.cc';

  String? _locale;
  ThemeMode _themeMode = ThemeMode.system;
  bool _developerMode = false;
  String _serverHost = defaultServerHost;
  String? _backgroundImagePath;
  bool _backgroundVisible = true;
  Color? _accentColor;

  String? get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  bool get developerMode => _developerMode;
  String get serverHost => _serverHost;
  String? get backgroundImagePath => _backgroundImagePath;

  /// Whether the configured background image is currently rendered. Toggling
  /// this off hides the image without deleting it.
  bool get backgroundVisible => _backgroundVisible;

  /// The user-selected seed color for the app theme. Null uses the default.
  Color? get accentColor => _accentColor;

  SettingsService() {
    ready = _load();
  }

  /// Completes once [SharedPreferences] has been read. The app awaits this
  /// before building so the persisted locale is applied on startup.
  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = prefs.getString(_keyLocale);
    final themeName = prefs.getString(_keyThemeMode);
    _themeMode = _themeNameToMode(themeName);
    _developerMode = prefs.getBool(_keyDeveloperMode) ?? false;
    _serverHost = prefs.getString(_keyServerHost) ?? defaultServerHost;
    _backgroundImagePath = prefs.getString(_keyBackgroundImagePath);
    _backgroundVisible = prefs.getBool(_keyBackgroundVisible) ?? true;
    final accent = prefs.getInt(_keyAccentColor);
    _accentColor = accent != null ? Color(accent) : null;
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

  Future<void> setDeveloperMode(bool value) async {
    _developerMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDeveloperMode, value);
    notifyListeners();
  }

  Future<void> setServerHost(String host) async {
    final normalized = host.trim().replaceAll(RegExp(r'/+$'), '');
    _serverHost = normalized.isEmpty ? defaultServerHost : normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerHost, _serverHost);
    notifyListeners();
  }

  Future<void> setBackgroundImagePath(String? path) async {
    _backgroundImagePath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_keyBackgroundImagePath);
    } else {
      await prefs.setString(_keyBackgroundImagePath, path);
    }
    notifyListeners();
  }

  Future<void> setBackgroundVisible(bool value) async {
    _backgroundVisible = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackgroundVisible, value);
    notifyListeners();
  }

  Future<void> setAccentColor(Color? color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_keyAccentColor);
    } else {
      await prefs.setInt(_keyAccentColor, color.toARGB32());
    }
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
