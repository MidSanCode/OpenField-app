import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/config/app_config.dart';
import 'package:openfield/core/log/log_overlay.dart';
import 'package:openfield/core/theme/app_theme.dart';
import 'package:openfield/core/widgets/color_wheel.dart';
import 'package:openfield/data/models/client_capabilities.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/realtime_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/pages/settings/permissions_page.dart';
import 'package:openfield/pages/settings/service_status_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings'.tr())),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: 'appSettings'.tr()),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                const _ThemeTile(),
                const Divider(height: 1),
                const _LanguageTile(),
                const Divider(height: 1),
                const _ServerHostTile(),
                const Divider(height: 1),
                const _AppColorTile(),
                const Divider(height: 1),
                const _BackgroundImageTile(),
                const Divider(height: 1),
                const _BackgroundVisibleTile(),
                const Divider(height: 1),
                const _CardOpacityTile(),
                const Divider(height: 1),
                _DeveloperModeTile(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'realtimeSettings'.tr()),
          const _RealtimeTile(),
          const SizedBox(height: 16),
          _SectionHeader(title: 'accountSettings'.tr()),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text('myPermissions'.tr()),
                  subtitle: Text('myPermissionsHint'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PermissionsPage()),
                    );
                  },
                ),
                const Divider(height: 1),
                const _RegionTile(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'about'.tr()),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text('about'.tr()),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${'version'.tr()} ${AppConfig.versionLabel}'),
                      Text('aboutDeveloper'.tr()),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: Text('serviceStatus'.tr()),
                  subtitle: Text('serviceStatusHint'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ServiceStatusPage()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text('capabilities'.tr()),
                  subtitle: Text('capabilitiesHint'.tr()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showCapabilitiesSheet(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Manual control over the realtime WebSocket connection: current state plus
/// buttons to reconnect after a failure, or disconnect/connect on demand.
class _RealtimeTile extends StatelessWidget {
  const _RealtimeTile();

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListenableBuilder(
        listenable: RealtimeService.instance,
        builder: (context, _) {
          final ws = RealtimeService.instance;
          final loggedIn = authService.accessToken != null;
          final stateLabel = _stateLabel(context, ws);
          final stateColor = _stateColor(context, ws);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wifi_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('realtimeSettings'.tr()),
                          const SizedBox(height: 2),
                          Text(
                            stateLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: stateColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ActionChip(
                      label: Text(
                        ws.isConnected
                            ? 'realtimeDisconnect'.tr()
                            : 'realtimeConnect'.tr(),
                      ),
                      onPressed: loggedIn ? () => _toggle(context, ws, authService) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: loggedIn ? ws.reconnect : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text('realtimeReconnect'.tr()),
                    ),
                    const Spacer(),
                    Text(
                      'retryCount'.tr(args: ['${ws.retryCount}']),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _stateLabel(BuildContext context, RealtimeService ws) {
    if (ws.isConnected) return 'realtimeConnected'.tr();
    if (ws.isDead) return 'realtimeDead'.tr();
    return 'realtimeDisconnected'.tr();
  }

  Color _stateColor(BuildContext context, RealtimeService ws) {
    if (ws.isConnected) {
      return Theme.of(context).colorScheme.primary;
    }
    if (ws.isDead) {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  void _toggle(BuildContext context, RealtimeService ws, AuthService authService) {
    if (ws.isConnected) {
      ws.disconnect();
    } else {
      final token = authService.accessToken;
      if (token != null) ws.connect(token);
    }
  }
}

/// Fetches the server capability matrix and shows it in a modal sheet so the
/// user can compare what this client supports against the running server.
Future<void> _showCapabilitiesSheet(BuildContext context) async {
  final theme = Theme.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('capabilities'.tr(), style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: ApiService().getCapabilities(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'loadFailed'.tr(),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final data = snapshot.data!;
                  final caps = data['capabilities'] as Map? ?? const {};
                  final version = data['version'] ?? '';
                  final serverKeys = caps.keys
                      .whereType<String>()
                      .toSet();
                  final clientKeys = ClientCapabilities.supported;
                  final allKeys =
                      (serverKeys.union(clientKeys)).toList()..sort();
                  // How many features each side supports over the unioned set.
                  final serverCount = allKeys
                      .where((k) => caps[k] == true)
                      .length;
                  final clientCount = allKeys
                      .where(clientKeys.contains)
                      .length;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (version is String && version.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${'serverVersion'.tr()} $version',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _CapabilityCount(
                              icon: Icons.phone_android,
                              label: 'capabilityClientCount'
                                  .tr(namedArgs: {'count': '$clientCount'}),
                              color: theme.colorScheme.primary,
                            ),
                            _CapabilityCount(
                              icon: Icons.dns_outlined,
                              label: 'capabilityServerCount'
                                  .tr(namedArgs: {'count': '$serverCount'}),
                              color: theme.colorScheme.tertiary,
                            ),
                          ],
                        ),
                      ),
                      ...allKeys.map(
                        (k) => _CapabilityRow(
                          name: k,
                          clientSupported: clientKeys.contains(k),
                          serverSupported: caps[k] == true,
                          theme: theme,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CapabilityCount extends StatelessWidget {
  const _CapabilityCount({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.name,
    required this.clientSupported,
    required this.serverSupported,
    required this.theme,
  });

  final String name;
  final bool clientSupported;
  final bool serverSupported;
  final ThemeData theme;

  IconData get _icon {
    if (clientSupported && serverSupported) return Icons.check_circle;
    if (clientSupported) return Icons.phone_android;
    return Icons.remove_circle_outline;
  }

  Color get _color {
    if (clientSupported && serverSupported) return theme.colorScheme.primary;
    if (clientSupported) return theme.colorScheme.tertiary;
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon, size: 20, color: _color),
      title: Text(
        name,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
      trailing: Text(
        serverSupported ? '✓' : '✗',
        style: theme.textTheme.labelMedium?.copyWith(
          color: serverSupported
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: Text('theme'.tr()),
      trailing: DropdownButton<ThemeMode>(
        value: settings.themeMode,
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(value: ThemeMode.system, child: Text('systemMode'.tr())),
          DropdownMenuItem(value: ThemeMode.light, child: Text('lightMode'.tr())),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('darkMode'.tr())),
        ],
        onChanged: (mode) {
          if (mode != null) settings.setThemeMode(mode);
        },
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text('language'.tr()),
      trailing: DropdownButton<String>(
        value: settings.locale,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: null, child: Text('Auto')),
          DropdownMenuItem(value: 'zh', child: Text('中文')),
          DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (value) {
          settings.setLocale(value);
          if (value == null) {
            context.resetLocale();
          } else {
            context.setLocale(Locale(value));
          }
        },
      ),
    );
  }
}

class _DeveloperModeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.bug_report_outlined),
          title: Text('developerMode'.tr()),
          subtitle: Text('developerModeHint'.tr()),
          value: settings.developerMode,
          onChanged: (value) async {
            await settings.setDeveloperMode(value);
          },
        ),
        if (settings.developerMode)
          ListTile(
            leading: const Icon(Icons.terminal),
            title: Text('logViewer'.tr()),
            subtitle: Text('logViewerHint'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => toggleLogOverlay(),
          ),
      ],
    );
  }
}

class _ServerHostTile extends StatelessWidget {
  const _ServerHostTile();

  Future<void> _openDialog(BuildContext context, SettingsService settings) async {
    final controller = TextEditingController(text: settings.serverHost);
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('serverHost'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'serverHostHint'.tr(),
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text('resetServerHost'.tr()),
                  onPressed: () {
                    controller.text = SettingsService.defaultServerHost;
                    setState(() => errorText = null);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('cancel'.tr()),
            ),
            TextButton(
              onPressed: () async {
                final input = controller.text;
                final validationError = SettingsService.validateServerHost(input);
                if (validationError != null) {
                  setState(() => errorText = validationError);
                  return;
                }
                final ok = await settings.setServerHost(input);
                if (!ok) {
                  setState(() => errorText = 'invalidServerHost'.tr());
                  return;
                }
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: Text('save'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: Text('serverHost'.tr()),
      subtitle: Text('serverHostHint'.tr()),
      onTap: () => _openDialog(context, settings),
      trailing: Text(
        settings.serverHost,
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Account region setting. Choosing a region applies its timezone to chat
/// timestamps and pushes the region + language to the server for notifications.
class _RegionTile extends StatelessWidget {
  const _RegionTile();

  /// Sentinel returned when the user picks "follow the device"; distinguishes
  /// a deliberate clear from dismissing the sheet (which returns null).
  static const _followDevice = RegionOption(
    code: '',
    labelKey: 'useDeviceTimezone',
    timezone: '',
    lang: '',
  );

  String _currentLabel(SettingsService settings) {
    final option = settings.regionOption;
    if (option != null) return option.labelKey.tr();
    return 'useDeviceTimezone'.tr();
  }

  /// Syncs the chosen region and its language to the server so server-pushed
  /// notifications use the right locale. Best effort: failures are surfaced
  /// quietly without blocking the local change.
  Future<void> _syncLocale(BuildContext context) async {
    final settings = Provider.of<SettingsService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await ApiService().updateLocale(token,
          region: settings.region, lang: settings.regionLang);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('localeSyncFailed'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.public_outlined),
      title: Text('regionSettings'.tr()),
      subtitle: Text('regionSettingsHint'.tr()),
      trailing: Text(
        _currentLabel(settings),
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        final selected = await showModalBottomSheet<RegionOption>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _RegionPicker(),
        );
        if (selected == null) return;
        if (identical(selected, _followDevice)) {
          await settings.setRegion(null);
        } else {
          await settings.setRegion(selected);
        }
        if (context.mounted) await _syncLocale(context);
      },
    );
  }
}

/// Scrollable list of named regions. Selecting "follow the device" clears the
/// region and its timezone; everything else applies the region's fixed offset.
class _RegionPicker extends StatelessWidget {
  const _RegionPicker();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final current = settings.region;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.public_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('regionSettings'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: current.isEmpty
                        ? const Icon(Icons.radio_button_checked)
                        : const Icon(Icons.radio_button_off),
                    title: Text('useDeviceTimezone'.tr()),
                    subtitle: Text('useDeviceTimezoneHint'.tr()),
                    onTap: () =>
                        Navigator.of(context).pop(_RegionTile._followDevice),
                  ),
                  for (final region in SettingsService.kRegions)
                    ListTile(
                      leading: current == region.code
                          ? const Icon(Icons.radio_button_checked)
                          : const Icon(Icons.radio_button_off),
                      title: Text(region.labelKey.tr()),
                      subtitle: Text('${region.timezone} · ${_langName(region.lang)}'),
                      onTap: () => Navigator.of(context).pop(region),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Human-readable name for a pushed language code, falling back to the raw
  /// code. Kept inline (no i18n keys) because these names are mostly identical
  /// across locales.
  static String _langName(String code) {
    switch (code) {
      case 'zh':
        return '中文';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'de':
        return 'Deutsch';
      case 'fr':
        return 'Français';
      case 'it':
        return 'Italiano';
      case 'es':
        return 'Español';
      case 'pt':
        return 'Português';
      case 'ru':
        return 'Русский';
      default:
        return 'English';
    }
  }
}

/// App theme color: preset palette, an option to extract a color from the
/// chosen background image, and a reset back to the default.
class _AppColorTile extends StatelessWidget {
  const _AppColorTile();

  static const List<Color> _palette = [
    Color(0xFF4CAF50), // default green
    Color(0xFF2196F3), // blue
    Color(0xFFF44336), // red
    Color(0xFF9C27B0), // purple
    Color(0xFFFF9800), // orange
    Color(0xFF00BCD4), // cyan
    Color(0xFF3F51B5), // indigo
    Color(0xFF607D8B), // blue grey
    Color(0xFF795548), // brown
  ];

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final accent = settings.accentColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('appColor'.tr()),
                    const SizedBox(height: 2),
                    Text(
                      'appColorHint'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _palette)
                _ColorDot(
                  color: color,
                  selected: accent == color,
                  onTap: () => settings.setAccentColor(color),
                ),
              Tooltip(
                message: 'appColorDefault'.tr(),
                child: _ColorDot(
                  color: AppTheme.seed,
                  selected: accent == null,
                  onTap: () => settings.setAccentColor(null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _pickCustom(context, settings),
                icon: const Icon(Icons.colorize_outlined, size: 18),
                label: Text('customColor'.tr()),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: settings.backgroundImagePath == null
                    ? null
                    : () => _pickFromBackground(settings),
                icon: const Icon(Icons.photo_outlined, size: 18),
                label: Text('pickFromBackground'.tr()),
              ),
              const SizedBox(width: 8),
              if (accent != null)
                TextButton(
                  onPressed: () => settings.setAccentColor(null),
                  child: Text('appColorDefault'.tr()),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context, SettingsService settings) async {
    final picked = await showColorWheelDialog(
      context: context,
      initialColor: settings.accentColor ?? AppTheme.seed,
      title: 'appColor'.tr(),
    );
    if (picked == null || !context.mounted) return;
    await settings.setAccentColor(picked);
  }

  Future<void> _pickFromBackground(SettingsService settings) async {
    final path = settings.backgroundImagePath;
    if (path == null) return;
    final color = await _averageColorOf(path);
    if (color != null) {
      await settings.setAccentColor(color);
    }
  }

  /// Samples a grid of pixels and returns their average color, used to derive
  /// an app theme color from the background image.
  Future<Color?> _averageColorOf(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData();
      image.dispose();
      if (data == null) return null;
      final raw = data.buffer.asUint8List();
      const samples = 8;
      var r = 0, g = 0, b = 0, count = 0;
      for (var y = 0; y < samples; y++) {
        for (var x = 0; x < samples; x++) {
          final px = (y * image.height ~/ samples) * image.width +
              (x * image.width ~/ samples);
          final i = px * 4;
          if (i + 3 >= raw.length) continue;
          r += raw[i];
          g += raw[i + 1];
          b += raw[i + 2];
          count++;
        }
      }
      if (count == 0) return null;
      return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
    } catch (_) {
      return null;
    }
  }
}

/// Card opacity: a slider that makes every card in the app translucent so the
/// theme / background colors show through. 100% is the default opaque surface.
class _CardOpacityTile extends StatelessWidget {
  const _CardOpacityTile();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final opacity = settings.cardOpacity;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.opacity_outlined, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('cardOpacity'.tr()),
                    const SizedBox(height: 2),
                    Text(
                      '${'cardOpacityHint'.tr()} ${(opacity * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: opacity,
            min: 0.2,
            max: 1.0,
            divisions: 16,
            label: '${(opacity * 100).round()}%',
            onChanged: (value) => settings.setCardOpacity(value),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: opacity >= 1.0
                    ? null
                    : () => settings.setCardOpacity(1.0),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text('appColorDefault'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.onPrimary)
            : null,
      ),
    );
  }
}

class _BackgroundImageTile extends StatefulWidget {
  const _BackgroundImageTile();

  @override
  State<_BackgroundImageTile> createState() => _BackgroundImageTileState();
}

class _BackgroundImageTileState extends State<_BackgroundImageTile> {
  bool _picking = false;

  Future<void> _pick(SettingsService settings) async {
    if (_picking) return;
    setState(() => _picking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // file_picker works on all platforms (mobile gallery, desktop file
      // dialog), unlike image_picker whose gallery source is not supported on
      // desktop and silently fails there.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single.path;
      if (picked == null) return;
      // Copy the selected file into a stable, app-owned location so the
      // background survives restarts and cache cleanups (the picker often
      // returns a path inside the OS temp/cache directory).
      final saved = await _copyToBackgroundDir(picked);
      await settings.setBackgroundImagePath(saved);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('backgroundImageSet'.tr())),
        );
      }
    } catch (e) {
      // A failure here previously left the background silently unset. Surface
      // it so the user knows the pick did not take effect.
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('backgroundImageSetFailed'.tr(
              namedArgs: {'error': e.toString()},
            )),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<String> _copyToBackgroundDir(String src) async {
    final dir = await _backgroundDir();
    // Extract the extension from the file name only. Taking the last dot of
    // the whole path picks up dots in ancestor directories and yields a
    // garbage destination that made File.copy throw on Windows paths like
    // "C:\Users\john.doe\Downloads\photo" -> dst ".../background.john.doe...".
    final name = src.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    final ext = (dot > 0 && dot < name.length - 1)
        ? name.substring(dot)
        : '.img';
    final dst = '${dir.path}/background$ext';
    await File(src).copy(dst);
    if (!await File(dst).exists()) {
      throw StateError('copy produced no file: $dst');
    }
    return dst;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final path = settings.backgroundImagePath;
    return ListTile(
      leading: _picking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : path == null
              ? const Icon(Icons.image_outlined)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Image.file(
                      File(path),
                      key: ValueKey('bg-preview:$path'),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined, size: 18),
                      ),
                    ),
                  ),
                ),
      title: Text('backgroundImage'.tr()),
      subtitle: Text(path ?? 'backgroundImageHint'.tr()),
      trailing: path == null
          ? const Icon(Icons.chevron_right)
          : TextButton(
              onPressed: _picking ? null : () => settings.setBackgroundImagePath(null),
              child: Text('clear'.tr()),
            ),
      onTap: _picking ? null : () => _pick(settings),
    );
  }
}

/// Resolves the directory used to persist the selected background image.
/// Computed once per call; cheap because the underlying call is memoized by
/// path_provider.
Future<Directory> _backgroundDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/background');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Temporarily hides the background image without deleting it.
class _BackgroundVisibleTile extends StatelessWidget {
  const _BackgroundVisibleTile();

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    final hasImage = settings.backgroundImagePath != null;
    return SwitchListTile(
      secondary: const Icon(Icons.visibility_outlined),
      title: Text('backgroundImageVisible'.tr()),
      subtitle: Text('backgroundImageVisibleHint'.tr()),
      value: hasImage ? settings.backgroundVisible : true,
      onChanged: hasImage ? (v) => settings.setBackgroundVisible(v) : null,
    );
  }
}
