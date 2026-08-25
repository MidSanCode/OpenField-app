import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:openfield/plugins/plugin_permissions.dart';

/// Colored chip showing a permission's security level.
class PermissionLevelChip extends StatelessWidget {
  final String permId;
  final bool dense;

  const PermissionLevelChip({super.key, required this.permId, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = permissionDefOf(permId);
    final (label, color) = switch (def?.level ?? PermissionLevel.critical) {
      PermissionLevel.safe => ('permLevelSafe'.tr(), Colors.green.shade700),
      PermissionLevel.normal => ('permLevelNormal'.tr(), theme.colorScheme.primary),
      PermissionLevel.sensitive => ('permLevelSensitive'.tr(), Colors.orange.shade800),
      PermissionLevel.critical => ('permLevelCritical'.tr(), theme.colorScheme.error),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 5 : 7, vertical: dense ? 1 : 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        def == null ? permId : def.labelKey.tr(),
        style: TextStyle(color: color, fontSize: dense ? 10 : 11),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Amber/red strip shown whenever the secure-boot gate is not online:
/// plugins are force-disabled and installs are blocked.
class SecureBootBanner extends StatelessWidget {
  final bool probing;

  const SecureBootBanner({super.key, required this.probing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = probing ? Colors.orange : theme.colorScheme.error;
    return Material(
      color: color.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.gpp_maybe_outlined, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                (probing
                        ? 'pluginSecureBootProbing'
                        : 'pluginSecureBootOffline')
                    .tr(),
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The per-permission consent dialog shown before a plugin may run.
/// Permissions are grouped by level; critical ones cannot be skipped.
class PermissionConsentDialog extends StatefulWidget {
  final String pluginName;
  final List<String> permissions;
  final Set<String> preGranted;
  final bool isStoreVerified;

  const PermissionConsentDialog({
    super.key,
    required this.pluginName,
    required this.permissions,
    this.preGranted = const {},
    this.isStoreVerified = false,
  });

  /// Returns the accepted permission set, or null when the user cancelled.
  static Future<Set<String>?> show(
    BuildContext context, {
    required String pluginName,
    required List<String> permissions,
    Set<String> preGranted = const {},
    bool isStoreVerified = false,
  }) {
    return showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PermissionConsentDialog(
        pluginName: pluginName,
        permissions: permissions,
        preGranted: preGranted,
        isStoreVerified: isStoreVerified,
      ),
    );
  }

  @override
  State<PermissionConsentDialog> createState() =>
      _PermissionConsentDialogState();
}

class _PermissionConsentDialogState extends State<PermissionConsentDialog> {
  late final Map<String, bool> _accepted;

  @override
  void initState() {
    super.initState();
    _accepted = {
      for (final p in widget.permissions) p: widget.preGranted.contains(p),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Group by level, most sensitive first.
    final byLevel = <PermissionLevel, List<String>>{};
    for (final p in widget.permissions) {
      byLevel.putIfAbsent(levelOf(p), () => []).add(p);
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.isStoreVerified ? Icons.verified : Icons.extension,
              size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('pluginConsentTitle'.tr())),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(
              text: widget.pluginName,
              style: theme.textTheme.titleSmall,
              children: [
                TextSpan(
                  text: ' ${'pluginConsentAsks'.tr()}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            )),
            if (!widget.isStoreVerified) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('pluginImportedWarning'.tr(),
                        style: theme.textTheme.bodySmall),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final level in PermissionLevel.values)
                      if (byLevel[level] != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(_levelTitle(level),
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: _levelColor(theme, level),
                                  fontWeight: FontWeight.w700)),
                        ),
                        for (final p in byLevel[level]!)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _accepted[p],
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(permissionDefOf(p)?.labelKey.tr() ?? p,
                                style: theme.textTheme.bodyMedium),
                            subtitle: Text(
                              permissionDefOf(p)?.hintKey.tr() ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                            onChanged: (v) =>
                                setState(() => _accepted[p] = v ?? false),
                          ),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _accepted.entries.where((e) => e.value).map((e) => e.key).toSet(),
          ),
          child: Text('confirm'.tr()),
        ),
      ],
    );
  }

  String _levelTitle(PermissionLevel level) => switch (level) {
        PermissionLevel.safe => 'permGroupSafe'.tr(),
        PermissionLevel.normal => 'permGroupNormal'.tr(),
        PermissionLevel.sensitive => 'permGroupSensitive'.tr(),
        PermissionLevel.critical => 'permGroupCritical'.tr(),
      };

  Color _levelColor(ThemeData theme, PermissionLevel level) =>
      switch (level) {
        PermissionLevel.safe => Colors.green.shade700,
        PermissionLevel.normal => theme.colorScheme.primary,
        PermissionLevel.sensitive => Colors.orange.shade800,
        PermissionLevel.critical => theme.colorScheme.error,
      };
}
