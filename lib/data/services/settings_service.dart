import 'dart:ui' show Color;

import 'package:easy_localization/easy_localization.dart';
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
  static const _keyTimezone = 'settings_timezone';
  static const String defaultServerHost = 'https://of-api.msc-studio.eu.cc';

  /// Sentinels for the client-side timezone setting. Empty means "follow the
  /// device's local timezone"; otherwise an IANA-free UTC offset label such as
  /// "UTC+8" or "UTC-5:30".
  static const String localTimezone = '';

  String? _locale;
  ThemeMode _themeMode = ThemeMode.system;
  bool _developerMode = false;
  String _serverHost = defaultServerHost;
  String? _backgroundImagePath;
  bool _backgroundVisible = true;
  Color? _accentColor;
  String _timezone = localTimezone;

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

  /// Client-side timezone: empty (follow device) or a fixed UTC offset label
  /// like "UTC+8". Server timestamps are converted to this zone for display.
  String get timezone => _timezone;

  /// Whether timestamps should render in the device's own local timezone.
  bool get usesDeviceTimezone => _timezone == localTimezone;

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
    _timezone = prefs.getString(_keyTimezone) ?? localTimezone;
    notifyListeners();
  }

  Future<void> setTimezone(String tz) async {
    _timezone = tz;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimezone, tz);
    notifyListeners();
  }

  /// Converts a server timestamp (UTC) into the client-selected timezone for
  /// display. Falls back to the device's local timezone when unset or when the
  /// stored label cannot be parsed.
  DateTime displayTime(DateTime utc) {
    if (usesDeviceTimezone) return utc.toLocal();
    final offset = _parseUtcOffset(_timezone);
    if (offset == null) return utc.toLocal();
    return utc.toUtc().add(offset);
  }

  /// Parses a label like "UTC+8", "UTC-5", "UTC+5:30" or "UTC-9:30" into a
  /// [Duration]. Returns null when the label is not a valid offset.
  static Duration? _parseUtcOffset(String label) {
    final m = RegExp(r'^UTC([+-])(\d{1,2})(?::(\d{2}))?$').firstMatch(label.trim());
    if (m == null) return null;
    final sign = m.group(1) == '-' ? -1 : 1;
    final hours = int.parse(m.group(2)!);
    final minutes = int.parse(m.group(3) ?? '0');
    if (hours > 14 || (hours == 14 && minutes > 0) || minutes >= 60) return null;
    return Duration(hours: sign * hours, minutes: sign * minutes);
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

  /// Validates a user-entered server host. Returns null when valid, or a
  /// human-readable error message describing the first problem found.
  ///
  /// Accepts either a bare host (`example.com`, `127.0.0.1:8080`) or a full
  /// URL (`https://example.com`). Rejects empty strings, unsupported schemes
  /// and anything `Uri.parse` cannot read.
  static String? validateServerHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return 'emptyServerHost'.tr();
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    Uri? uri;
    try {
      uri = Uri.parse(withScheme);
    } catch (_) {
      return 'invalidServerHost'.tr();
    }
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'invalidServerHost'.tr();
    }
    if (uri.host.isEmpty) return 'invalidServerHost'.tr();
    return null;
  }

  Future<bool> setServerHost(String host) async {
    if (validateServerHost(host) != null) return false;
    var normalized = host.trim().replaceAll(RegExp(r'/+$'), '');
    if (!normalized.contains('://')) {
      normalized = 'http://$normalized';
    }
    _serverHost = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerHost, _serverHost);
    notifyListeners();
    return true;
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
