import 'dart:ui' show Color;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' show ChangeNotifier, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openfield/core/log/log_recorder.dart';

/// A named region the user can pick that bundles a timezone offset, a display
/// name (via an i18n key) and the language used for server-pushed
/// notifications. Choosing a region is a shortcut for setting all three.
class RegionOption {
  final String code;
  final String labelKey;
  final String timezone;
  final String lang;

  const RegionOption({
    required this.code,
    required this.labelKey,
    required this.timezone,
    required this.lang,
  });
}

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
  static const _keyCardOpacity = 'settings_card_opacity';
  static const _keyTimezone = 'settings_timezone';
  static const _keyRegion = 'settings_region';
  static const _keyRegionLang = 'settings_region_lang';
  static const _keyEncryptAttachments = 'settings_encrypt_attachments';
  static const String defaultServerHost = 'https://api.openfield.eu.cc';

  /// Sentinels for the client-side timezone setting. Empty means "follow the
  /// device's local timezone"; otherwise an IANA-free UTC offset label such as
  /// "UTC+8" or "UTC-5:30".
  static const String localTimezone = '';

  /// Sentinels for the region setting. A null/empty region means "follow the
  /// device" and clears the server-pushed language.
  static const String localRegion = '';

  /// Known regions offered in the region picker. Each bundles a timezone
  /// offset for local timestamp display and the server-push notification
  /// language.
  static const List<RegionOption> kRegions = [
    RegionOption(
      code: 'zh-CN',
      labelKey: 'regionCn',
      timezone: 'UTC+8',
      lang: 'zh',
    ),
    RegionOption(
      code: 'zh-TW',
      labelKey: 'regionTw',
      timezone: 'UTC+8',
      lang: 'zh',
    ),
    RegionOption(
      code: 'zh-HK',
      labelKey: 'regionHk',
      timezone: 'UTC+8',
      lang: 'zh',
    ),
    RegionOption(
      code: 'en-US',
      labelKey: 'regionUs',
      timezone: 'UTC-5',
      lang: 'en',
    ),
    RegionOption(
      code: 'en-GB',
      labelKey: 'regionGb',
      timezone: 'UTC+0',
      lang: 'en',
    ),
    RegionOption(
      code: 'en-AU',
      labelKey: 'regionAu',
      timezone: 'UTC+10',
      lang: 'en',
    ),
    RegionOption(
      code: 'ja-JP',
      labelKey: 'regionJp',
      timezone: 'UTC+9',
      lang: 'ja',
    ),
    RegionOption(
      code: 'ko-KR',
      labelKey: 'regionKr',
      timezone: 'UTC+9',
      lang: 'ko',
    ),
    RegionOption(
      code: 'de-DE',
      labelKey: 'regionDe',
      timezone: 'UTC+1',
      lang: 'de',
    ),
    RegionOption(
      code: 'fr-FR',
      labelKey: 'regionFr',
      timezone: 'UTC+1',
      lang: 'fr',
    ),
    RegionOption(
      code: 'it-IT',
      labelKey: 'regionIt',
      timezone: 'UTC+1',
      lang: 'it',
    ),
    RegionOption(
      code: 'es-ES',
      labelKey: 'regionEs',
      timezone: 'UTC+1',
      lang: 'es',
    ),
    RegionOption(
      code: 'pt-BR',
      labelKey: 'regionBr',
      timezone: 'UTC-3',
      lang: 'pt',
    ),
    RegionOption(
      code: 'ru-RU',
      labelKey: 'regionRu',
      timezone: 'UTC+3',
      lang: 'ru',
    ),
  ];

  String? _locale;
  ThemeMode _themeMode = ThemeMode.system;
  bool _developerMode = false;
  String _serverHost = defaultServerHost;
  String? _backgroundImagePath;
  bool _backgroundVisible = true;
  Color? _accentColor;
  double _cardOpacity = 1.0;
  String _timezone = localTimezone;
  String _region = localRegion;
  String _regionLang = '';
  bool _encryptAttachments = false;

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

  /// Opacity applied to cards app-wide (0.0-1.0). 1.0 keeps the default opaque
  /// surface so cards read like solid floating panels; lower values let theme /
  /// background colors bleed through.
  double get cardOpacity => _cardOpacity;

  /// Client-side timezone: empty (follow device) or a fixed UTC offset label
  /// like "UTC+8". Server timestamps are converted to this zone for display.
  String get timezone => _timezone;

  /// Whether timestamps should render in the device's own local timezone.
  bool get usesDeviceTimezone => _timezone == localTimezone;

  /// The selected region code (e.g. "zh-CN"), or empty when following the
  /// device. Drives the display name in the region picker.
  String get region => _region;

  /// The language code pushed to the server for notifications (e.g. "zh"),
  /// derived from the selected region.
  String get regionLang => _regionLang;

  /// Whether files sent in end-to-end-encrypted conversations are encrypted
  /// client-side before upload. Off by default: attachments upload directly
  /// (room-private as usual), which keeps large uploads fast and avoids the
  /// full-file encrypt pass. Text messages are always encrypted regardless.
  bool get encryptAttachments => _encryptAttachments;

  /// The [RegionOption] matching the current [region], or null when none.
  RegionOption? get regionOption {
    if (_region.isEmpty) return null;
    for (final r in kRegions) {
      if (r.code == _region) return r;
    }
    return null;
  }

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
    _cardOpacity = (prefs.getDouble(_keyCardOpacity) ?? 1.0).clamp(0.0, 1.0);
    _timezone = prefs.getString(_keyTimezone) ?? localTimezone;
    _region = prefs.getString(_keyRegion) ?? localRegion;
    _regionLang = prefs.getString(_keyRegionLang) ?? '';
    _encryptAttachments = prefs.getBool(_keyEncryptAttachments) ?? false;
    notifyListeners();
  }

  Future<void> setTimezone(String tz) async {
    _timezone = tz;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimezone, tz);
    notifyListeners();
  }

  /// Applies a region, setting its timezone offset for display and its
  /// notification language. Passing null/empty clears the region (follow the
  /// device). Returns the new region and the pushed language so callers can
  /// sync the server via PUT /users/me/locale.
  Future<void> setRegion(RegionOption? option) async {
    final prefs = await SharedPreferences.getInstance();
    if (option == null) {
      _region = localRegion;
      _regionLang = '';
      _timezone = localTimezone;
      await prefs.remove(_keyRegion);
      await prefs.remove(_keyRegionLang);
      await prefs.remove(_keyTimezone);
    } else {
      _region = option.code;
      _regionLang = option.lang;
      _timezone = option.timezone;
      await prefs.setString(_keyRegion, option.code);
      await prefs.setString(_keyRegionLang, option.lang);
      await prefs.setString(_keyTimezone, option.timezone);
    }
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
    LogService.instance.setEnabled(value);
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

  Future<void> setCardOpacity(double value) async {
    _cardOpacity = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCardOpacity, _cardOpacity);
    notifyListeners();
  }

  Future<void> setEncryptAttachments(bool value) async {
    _encryptAttachments = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEncryptAttachments, value);
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
