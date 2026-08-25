import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/plugins/plugin_detail_page.dart';
import 'package:openfield/pages/plugins/plugin_store_page.dart';
import 'package:openfield/pages/plugins/plugin_widgets.dart';
import 'package:openfield/plugins/plugin_gate.dart';
import 'package:openfield/plugins/plugin_manager.dart';
import 'package:openfield/plugins/plugin_permissions.dart';

/// Main plugin management page: installed list, secure-boot status, import
/// and store entry points.
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    PluginManager.instance.ensureInitialized();
  }

  Future<void> _importPlugin() async {
    final gate = context.read<PluginGate>();
    if (!gate.allowsPlugins) {
      _snack('pluginBlockedOffline'.tr());
      return;
    }
    final token = context.read<AuthService>().accessToken;
    if (token == null) {
      _snack('pluginNeedLogin'.tr());
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    final picked = result?.files;
    final data = (picked != null && picked.length == 1) ? picked.first.bytes : null;
    if (data == null || !mounted) return;

    setState(() => _importing = true);
    try {
      final installed = await PluginManager.instance.installBundle(
        data,
        origin: PluginOrigin.imported,
        verified: false,
      );
      if (!mounted) return;
      final granted = await PermissionConsentDialog.show(
        context,
        pluginName: '${installed.manifest.name} v${installed.manifest.version}',
        permissions: installed.manifest.permissions,
        isStoreVerified: false,
      );
      if (granted == null || !mounted) {
        // Cancelled → remove the half-installed bundle.
        await PluginManager.instance.uninstall(installed.manifest.id);
        return;
      }
      await PluginManager.instance.setGrants(installed.manifest.id, granted);
      if (granted.isNotEmpty) {
        await PluginManager.instance.enable(installed.manifest.id);
      }
      if (mounted) _snack('pluginImported'.tr());
    } catch (e) {
      if (mounted) _snack('pluginInstallFailed'.tr(args: [e.toString()]));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final manager = Provider.of<PluginManager>(context);
    final gate = Provider.of<PluginGate>(context);
    final plugins = manager.plugins;

    return Scaffold(
      appBar: AppBar(
        title: Text('plugins'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'refresh'.tr(),
            onPressed: () => gate.probe(),
          ),
        ],
      ),
      body: Column(
        children: [
          SecureBootBanner(probing: gate.state == PluginGateState.probing),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        gate.allowsPlugins && !_importing ? _openStore : null,
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text('pluginStore'.tr()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        gate.allowsPlugins && !_importing ? _importPlugin : null,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_open_outlined),
                    label: Text('pluginImport'.tr()),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: plugins.isEmpty
                ? _buildEmpty(context)
                : RefreshIndicator(
                    onRefresh: () => PluginGate.instance.probe(),
                    child: ListView.separated(
                      itemCount: plugins.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) {
                        final p = plugins[i];
                        return _PluginTile(
                          pluginId: p.manifest.id,
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PluginDetailPage(pluginId: p.manifest.id),
                            ));
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openStore() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PluginStorePage()),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.extension_outlined,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('pluginEmpty'.tr()),
          const SizedBox(height: 6),
          Text('pluginEmptyHint'.tr(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PluginTile extends StatelessWidget {
  final String pluginId;
  final VoidCallback onTap;

  const _PluginTile({required this.pluginId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = Provider.of<PluginManager>(context);
    final installed = manager.plugin(pluginId)!;
    final manifest = installed.manifest;
    final enabled = manager.isEnabled(pluginId);
    final running = manager.isRunning(pluginId);
    final criticalPerms = manifest
        .permissions
        .where((p) => levelOf(p) == PermissionLevel.critical)
        .length;

    return ListTile(
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor:
                theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
            child: Icon(
              Icons.extension,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          if (running)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(manifest.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (installed.verifiedFromStore)
            Icon(Icons.verified, size: 16, color: theme.colorScheme.primary)
          else
            Tooltip(
              message: 'pluginUnverifiedBadge'.tr(),
              child: Icon(Icons.help_outline,
                  size: 15, color: theme.colorScheme.outline),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'v${manifest.version}'
            '${installed.origin == PluginOrigin.store ? '' : ' · ${'pluginSourceImported'.tr()}'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 4,
            runSpacing: 3,
            children: [
              for (final p in manifest.permissions.take(3))
                PermissionLevelChip(permId: p, dense: true),
              if (criticalPerms > 3 || manifest.permissions.length > 3)
                Text('+${manifest.permissions.length - 3}',
                    style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
      trailing: Switch(
        value: enabled,
        onChanged: (v) async {
          if (v && !manager.isGrantedAll(manifest.id, manifest.permissions)) {
            final granted = await PermissionConsentDialog.show(
              context,
              pluginName: manifest.name,
              permissions: manifest.permissions,
              preGranted: manager.grantsOf(manifest.id),
              isStoreVerified: installed.verifiedFromStore,
            );
            if (granted == null) return;
            await PluginManager.instance.setGrants(manifest.id, granted);
            if (granted.isEmpty) return;
          }
          if (v) {
            await PluginManager.instance.enable(manifest.id);
          } else {
            await PluginManager.instance.disable(manifest.id);
          }
        },
      ),
    );
  }
}
