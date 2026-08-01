import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/log/log_overlay.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/settings/permissions_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: l10n.appSettings),
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
                const _BackgroundImageTile(),
                const Divider(height: 1),
                _DeveloperModeTile(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: l10n.accountSettings),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(l10n.myPermissions),
                  subtitle: Text(l10n.myPermissionsHint),
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
          _SectionHeader(title: l10n.about),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.about),
              subtitle: Text('${l10n.version} 1.0.0'),
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
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: Text(l10n.theme),
      trailing: DropdownButton<ThemeMode>(
        value: settings.themeMode,
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.systemMode)),
          DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.lightMode)),
          DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.darkMode)),
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
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l10n.language),
      trailing: DropdownButton<String>(
        value: settings.locale,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: null, child: Text('Auto')),
          DropdownMenuItem(value: 'zh', child: Text('中文')),
          DropdownMenuItem(value: 'en', child: Text('English')),
        ],
        onChanged: (value) => settings.setLocale(value),
      ),
    );
  }
}

class _DeveloperModeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsService>(context);
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.bug_report_outlined),
          title: Text(l10n.developerMode),
          subtitle: Text(l10n.developerModeHint),
          value: settings.developerMode,
          onChanged: (value) async {
            await settings.setDeveloperMode(value);
          },
        ),
        if (settings.developerMode)
          ListTile(
            leading: const Icon(Icons.terminal),
            title: Text(l10n.logViewer),
            subtitle: Text(l10n.logViewerHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => toggleLogOverlay(),
          ),
      ],
    );
  }
}

class _ServerHostTile extends StatelessWidget {
  const _ServerHostTile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: Text(l10n.serverHost),
      subtitle: Text(l10n.serverHostHint),
      onTap: () async {
        final controller = TextEditingController(text: settings.serverHost);
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.serverHost),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(hintText: l10n.serverHostHint),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text(l10n.save),
              ),
            ],
          ),
        );
        if (result != null) {
          await settings.setServerHost(result);
        }
      },
      trailing: Text(
        settings.serverHost,
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _BackgroundImageTile extends StatelessWidget {
  const _BackgroundImageTile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsService>(context);
    return ListTile(
      leading: const Icon(Icons.image_outlined),
      title: Text(l10n.backgroundImage),
      subtitle: Text(l10n.backgroundImageHint),
      trailing: settings.backgroundImagePath == null
          ? const Icon(Icons.chevron_right)
          : TextButton(
              onPressed: () => settings.setBackgroundImagePath(null),
              child: Text(l10n.clear),
            ),
      onTap: () async {
        final picker = ImagePicker();
        final result = await picker.pickImage(source: ImageSource.gallery);
        if (result == null) return;
        await settings.setBackgroundImagePath(result.path);
      },
    );
  }
}
