import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/data/services/api_service.dart';

/// Live status of every backend service, fetched from the gateway's aggregate
/// health endpoint. Reachable from Settings; useful to tell "the app is
/// broken" from "one service is down".
class ServiceStatusPage extends StatefulWidget {
  const ServiceStatusPage({super.key});

  @override
  State<ServiceStatusPage> createState() => _ServiceStatusPageState();
}

class _ServiceStatusPageState extends State<ServiceStatusPage> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep the page honest when left open.
    _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _apiService.getServicesHealth();
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services =
        (_data?['services'] as Map?)?.cast<String, dynamic>() ?? const {};
    final allHealthy = _data?['all_healthy'] as bool? ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('serviceStatus'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'refresh'.tr(),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(theme, services, allHealthy),
    );
  }

  Widget _buildBody(
      ThemeData theme, Map<String, dynamic> services, bool allHealthy) {
    if (_isLoading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('loadFailed'.tr()),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: Text('retry'.tr())),
          ],
        ),
      );
    }
    final entries = services.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    allHealthy ? Icons.verified_outlined : Icons.warning_amber_outlined,
                    color: allHealthy ? Colors.green.shade600 : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      allHealthy
                          ? 'serviceAllHealthy'.tr()
                          : 'serviceDegraded'.tr(),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_isLoading)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ServiceTile(name: entries[i].key, report: entries[i].value),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'serviceAutoRefreshHint'.tr(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final String name;
  final dynamic report;

  const _ServiceTile({required this.name, required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final map = report is Map ? (report as Map).cast<String, dynamic>() : <String, dynamic>{};
    final status = map['status'] as String? ?? 'unknown';
    final latency = map['latency_ms'] as num? ?? 0;
    final error = map['error'] as String?;
    final details =
        (map['details'] as Map?)?.cast<String, dynamic>() ?? const {};

    final healthy = status == 'up';
    final icon = healthy
        ? Icons.check_circle
        : (status == 'degraded'
            ? Icons.help_outline
            : Icons.cancel);
    final color = healthy
        ? Colors.green.shade600
        : (status == 'degraded' ? Colors.orange.shade600 : theme.colorScheme.error);

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text('serviceName_$name'.tr()),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null && error.isNotEmpty)
            Text(error, maxLines: 2, overflow: TextOverflow.ellipsis),
          for (final e in details.entries)
            Text(
              '${'serviceName_${e.key}'.tr()}: ${e.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Text(
        '${latency}ms',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
