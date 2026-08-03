import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  final ApiService _apiService = ApiService();
  List<String> _permissions = [];
  List<String> _groups = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _apiService.getMyPermissions(token);
      if (!mounted) return;
      setState(() {
        _permissions = (data['permissions'] as List?)?.whereType<String>().toList() ?? [];
        _groups = (data['groups'] as List?)?.whereType<String>().toList() ?? [];
        _isLoading = false;
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
    return Scaffold(
      appBar: AppBar(title: Text('myPermissions'.tr())),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('myGroups'.tr(), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_groups.isEmpty)
          Text('noGroups'.tr(), style: Theme.of(context).textTheme.bodyMedium)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _groups
                .map((g) => Chip(label: Text(g), avatar: const Icon(Icons.groups_outlined, size: 18)))
                .toList(),
          ),
        const SizedBox(height: 24),
        Text('myPermissions'.tr(), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_permissions.isEmpty)
          Text('noPermissions'.tr(), style: Theme.of(context).textTheme.bodyMedium)
        else
          ..._permissions.map(
            (p) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.check_circle_outline,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(p, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
          ),
      ],
    );
  }
}
