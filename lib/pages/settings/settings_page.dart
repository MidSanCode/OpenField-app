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
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/pages/settings/permissions_page.dart';

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
                _DeveloperModeTile(),
              ],
            ),
          ),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'about'.tr()),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
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
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<String> _copyToBackgroundDir(String src) async {
    final dir = await _backgroundDir();
    final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')) : '.img';
    final dst = '${dir.path}/background$ext';
    await File(src).copy(dst);
    return dst;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: _picking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.image_outlined),
      title: Text('backgroundImage'.tr()),
      subtitle: Text('backgroundImageHint'.tr()),
      trailing: settings.backgroundImagePath == null
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
