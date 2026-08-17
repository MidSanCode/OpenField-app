import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/widgets/attachment_view.dart' show formatBytes;

/// One storage bucket returned by the account service.
class StorageBucketInfo {
  final String name;
  final String label;
  final int defaultQuota;
  final int minMemberLevel;
  final bool isDefault;
  final bool locked;

  const StorageBucketInfo({
    required this.name,
    required this.label,
    required this.defaultQuota,
    required this.minMemberLevel,
    required this.isDefault,
    required this.locked,
  });

  factory StorageBucketInfo.fromJson(Map<String, dynamic> json) {
    return StorageBucketInfo(
      name: (json['name'] as String?) ?? '',
      label: (json['label'] as String?) ?? ((json['name'] as String?) ?? ''),
      defaultQuota: (json['default_quota'] as num?)?.toInt() ?? 0,
      minMemberLevel: (json['min_member_level'] as num?)?.toInt() ?? 0,
      isDefault: json['is_default'] == true,
      locked: json['locked'] == true,
    );
  }
}

class StorageBucketPage extends StatefulWidget {
  const StorageBucketPage({super.key});

  @override
  State<StorageBucketPage> createState() => _StorageBucketPageState();
}

class _StorageBucketPageState extends State<StorageBucketPage> {
  final ApiService _apiService = ApiService();
  List<StorageBucketInfo> _buckets = [];
  String _current = '';
  bool _isLoading = true;
  bool _switching = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _apiService.listStorageBuckets(auth.accessToken!);
      if (!mounted) return;
      setState(() {
        _buckets = (data['buckets'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(StorageBucketInfo.fromJson)
            .toList();
        _current = (data['current'] as String?) ?? '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _switch(StorageBucketInfo bucket) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => _switching = true);
    try {
      final user = await _apiService.setStorageBucket(auth.accessToken!, bucket.name);
      await auth.fetchCurrentUser();
      if (!mounted) return;
      setState(() {
        _current = user.storageBucket.isNotEmpty ? user.storageBucket : bucket.name;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('storageBucketSwitched'.tr())),
        );
      }
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('storageBucket'.tr())),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text('retry'.tr()),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                      child: Text(
                        'storageBucketHint'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ..._buckets.map((bucket) => _buildTile(theme, bucket)),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _buildTile(ThemeData theme, StorageBucketInfo bucket) {
    final selected = bucket.name == _current;
    final canSelect = !bucket.locked;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          bucket.isDefault ? Icons.storage_rounded : Icons.cloud_outlined,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text(bucket.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('storageQuotaDefault'.tr(namedArgs: {
              'quota': formatBytes(bucket.defaultQuota),
            })),
            if (bucket.minMemberLevel > 0) ...[
              const SizedBox(height: 2),
              Text(
                'storageBucketRequiresLevel'.tr(namedArgs: {
                  'level': '${bucket.minMemberLevel}',
                }),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: bucket.locked ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (bucket.isDefault) ...[
              const SizedBox(height: 2),
              Text(
                'storageBucketDefault'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
        trailing: selected
            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
            : const Icon(Icons.chevron_right),
        enabled: canSelect && !_switching,
        onTap: canSelect && !selected && !_switching
            ? () => _switch(bucket)
            : bucket.locked
                ? () => _showLockedDialog(bucket)
                : null,
      ),
    );
  }

  void _showLockedDialog(StorageBucketInfo bucket) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('storageBucketLocked'.tr()),
        content: Text('storageBucketLockedHint'.tr(namedArgs: {
          'level': '${bucket.minMemberLevel}',
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('ok'.tr()),
          ),
        ],
      ),
    );
  }
}