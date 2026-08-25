import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:openfield/pages/plugins/plugin_widgets.dart';
import 'package:openfield/plugins/plugin_gate.dart';
import 'package:openfield/plugins/plugin_manager.dart';
import 'package:openfield/plugins/plugin_permissions.dart';

/// Full metadata + controls for one installed plugin.
class PluginDetailPage extends StatelessWidget {
  final String pluginId;

  const PluginDetailPage({super.key, required this.pluginId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = Provider.of<PluginManager>(context);
    final installed = manager.plugin(pluginId);
    if (installed == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('pluginMissing'.tr())),
      );
    }
    final manifest = installed.manifest;
    final enabled = manager.isEnabled(pluginId);

    return Scaffold(
      appBar: AppBar(
        title: Text(manifest.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                child: Icon(Icons.extension,
                    size: 30, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(manifest.name,
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (installed.verifiedFromStore) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.verified,
                            size: 18, color: theme.colorScheme.primary),
                      ],
                    ]),
                    Text('v${manifest.version} · ${manifest.author}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if (manifest.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(manifest.description, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),

          // Status card
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  _StatusRow(
                    icon: Icons.power_settings_new,
                    label: 'pluginStateEnabled'.tr(),
                    trailing: Switch(
                      value: enabled,
                      onChanged: (v) async {
                        final gate = context.read<PluginGate>();
                        if (v && !gate.allowsPlugins) return;
                        if (v &&
                            !manager.isGrantedAll(
                                pluginId, manifest.permissions)) {
                          final granted = await PermissionConsentDialog.show(
                            context,
                            pluginName: manifest.name,
                            permissions: manifest.permissions,
                            preGranted: manager.grantsOf(pluginId),
                            isStoreVerified: installed.verifiedFromStore,
                          );
                          if (granted == null) return;
                          await PluginManager.instance
                              .setGrants(pluginId, granted);
                          if (granted.isEmpty) return;
                        }
                        v
                            ? PluginManager.instance.enable(pluginId)
                            : PluginManager.instance.disable(pluginId);
                      },
                    ),
                  ),
                  const Divider(),
                  _StatusRow(
                    icon: Icons.bolt,
                    label: 'pluginStateRuntime'.tr(),
                    trailing: Text(
                      manager.isRunning(pluginId)
                          ? 'pluginRuntimeRunning'.tr()
                          : (enabled
                              ? 'pluginRuntimeStopped'.tr()
                              : 'pluginRuntimeOff'.tr()),
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: manager.isRunning(pluginId)
                              ? Colors.green.shade700
                              : theme.colorScheme.outline),
                    ),
                  ),
                  const Divider(),
                  _StatusRow(
                    icon: installed.origin == PluginOrigin.store
                        ? Icons.storefront_outlined
                        : Icons.file_open_outlined,
                    label: 'pluginSource'.tr(),
                    trailing: Text(
                      installed.origin == PluginOrigin.store
                          ? 'pluginSourceStore'.tr()
                          : 'pluginSourceImported'.tr(),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Permissions section
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('pluginPermissionsSection'.tr(),
                style: theme.textTheme.titleMedium),
          ),
          if (manifest.permissions.isEmpty)
            Text('pluginPermissionsNone'.tr(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline))
          else ...[
            for (final p in manifest.permissions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(_levelIcon(levelOf(p)),
                    color: theme.colorScheme.primary, size: 20),
                title: Text(permissionDefOf(p)?.labelKey.tr() ?? p),
                subtitle: Text(permissionDefOf(p)?.hintKey.tr() ?? '',
                    style: theme.textTheme.bodySmall),
                trailing: PermissionLevelChip(permId: p),
              ),
            TextButton.icon(
              onPressed: () async {
                final granted = await PermissionConsentDialog.show(
                  context,
                  pluginName: manifest.name,
                  permissions: manifest.permissions,
                  preGranted: manager.grantsOf(pluginId),
                  isStoreVerified: installed.verifiedFromStore,
                );
                if (granted != null) {
                  await PluginManager.instance.setGrants(pluginId, granted);
                }
              },
              icon: const Icon(Icons.tune, size: 18),
              label: Text('pluginEditGrants'.tr()),
            ),
          ],

          // Metadata
          const SizedBox(height: 8),
          if (manifest.allowedHosts.isNotEmpty) ...[
            Text('pluginAllowedHosts'.tr(), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final h in manifest.allowedHosts)
                  Chip(label: Text(h), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          if (manifest.minAppVersion.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${'pluginMinAppVersion'.tr()} ${manifest.minAppVersion}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],

          // Danger zone
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
            ),
            icon: const Icon(Icons.delete_outline),
            label: Text('pluginUninstall'.tr()),
            onPressed: () => _confirmUninstall(context),
          ),
        ],
      ),
    );
  }

  IconData _levelIcon(PermissionLevel level) => switch (level) {
        PermissionLevel.safe => Icons.lock_open,
        PermissionLevel.normal => Icons.link,
        PermissionLevel.sensitive => Icons.warning_amber_outlined,
        PermissionLevel.critical => Icons.gpp_bad_outlined,
      };

  Future<void> _confirmUninstall(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('pluginUninstallTitle'.tr()),
        content: Text('pluginUninstallBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await PluginManager.instance.uninstall(pluginId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        trailing,
      ],
    );
  }
}
