import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/plugins/plugin_widgets.dart';
import 'package:openfield/plugins/plugin_manager.dart';

/// Browses the server-side plugin store and installs bundles.
class PluginStorePage extends StatefulWidget {
  const PluginStorePage({super.key});

  @override
  State<PluginStorePage> createState() => _PluginStorePageState();
}

class _PluginStorePageState extends State<PluginStorePage> {
  late Future<List<StorePlugin>> _future;

  @override
  void initState() {
    super.initState();
    PluginManager.instance.ensureInitialized();
    _future = _load();
  }

  Future<List<StorePlugin>> _load() async {
    final token = context.read<AuthService>().accessToken;
    return ApiService().listStorePlugins(token);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _install(StorePlugin storePlugin) async {
    final auth = context.read<AuthService>();
    final token = auth.accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('pluginNeedLogin'.tr())));
      return;
    }
    try {
      final bytes = await ApiService().downloadStorePlugin(token, storePlugin.id);
      if (!mounted) return;
      final installed = await PluginManager.instance.installBundle(
        bytes,
        origin: PluginOrigin.store,
        verified: true,
      );
      if (!mounted) return;
      final granted = await PermissionConsentDialog.show(
        context,
        pluginName: '${installed.manifest.name} v${installed.manifest.version}',
        permissions: installed.manifest.permissions,
        isStoreVerified: true,
      );
      if (granted == null || !mounted) {
        await PluginManager.instance.uninstall(installed.manifest.id);
        return;
      }
      await PluginManager.instance.setGrants(installed.manifest.id, granted);
      if (granted.isNotEmpty) {
        await PluginManager.instance.enable(installed.manifest.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('pluginInstalled'.tr())));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('pluginInstallFailed'.tr(args: [e.toString()]))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('pluginStore'.tr()),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: FutureBuilder<List<StorePlugin>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 44, color: theme.colorScheme.outline),
                  const SizedBox(height: 10),
                  Text('${snap.error}',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _reload, child: Text('retry'.tr())),
                ],
              ),
            );
          }
          final plugins = snap.data ?? const [];
          if (plugins.isEmpty) {
            return Center(child: Text('pluginStoreEmpty'.tr()));
          }
          return ListView.separated(
            itemCount: plugins.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) =>
                _StoreTile(plugin: plugins[i], onInstall: () => _install(plugins[i])),
          );
        },
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  final StorePlugin plugin;
  final VoidCallback onInstall;

  const _StoreTile({required this.plugin, required this.onInstall});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = Provider.of<PluginManager>(context);
    final installed = manager.plugin(plugin.id) != null;
    final upToDate = installed &&
        manager.plugin(plugin.id)!.manifest.version == plugin.version;

    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor:
            theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
        child: Icon(Icons.extension,
            color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Row(children: [
        Expanded(
          child: Text(plugin.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (plugin.verified)
          Icon(Icons.verified, size: 16, color: theme.colorScheme.primary),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plugin.description.isNotEmpty)
            Text(plugin.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
          const SizedBox(height: 3),
          Wrap(
            spacing: 4,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('v${plugin.version} · ${plugin.author}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              for (final p in plugin.permissions.take(4))
                PermissionLevelChip(permId: p, dense: true),
            ],
          ),
        ],
      ),
      trailing: upToDate
          ? Text('pluginAlreadyInstalled'.tr(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline))
          : FilledButton.tonal(
              onPressed: installed ? null : onInstall,
              child: Text(installed
                  ? 'pluginUpdateUnavailable'.tr()
                  : 'pluginInstallAction'.tr()),
            ),
    );
  }
}
