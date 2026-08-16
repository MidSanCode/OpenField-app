import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/consent_request.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:easy_localization/easy_localization.dart';

class ConsentRequestsPage extends StatefulWidget {
  const ConsentRequestsPage({super.key});

  @override
  State<ConsentRequestsPage> createState() => _ConsentRequestsPageState();
}

class _ConsentRequestsPageState extends State<ConsentRequestsPage> {
  final ApiService _apiService = ApiService();
  List<ConsentRequest> _requests = [];
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
      final requests = await _apiService.listConsentRequests(token);
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _accept(ConsentRequest request) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.acceptConsentRequest(token, request.id);
      if (!mounted) return;
      setState(() {
        _requests = _requests.where((r) => r.id != request.id).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _decline(ConsentRequest request) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.declineConsentRequest(token, request.id);
      if (!mounted) return;
      setState(() {
        _requests = _requests.where((r) => r.id != request.id).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('chatRequests'.tr())),
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
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_email_read_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('chatRequestsEmpty'.tr()),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _requests.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final request = _requests[index];
          return ListTile(
            leading: Avatar(
              radius: 22,
              imageUrl: request.requesterAvatar ?? '',
              fallbackIcon: Icons.person,
            ),
            title: Text(request.requesterDisplay),
            subtitle: Text(
              request.isGroupInvite
                  ? '${'chatRequestTypeGroup'.tr()}}: ${request.groupTitle ?? ''}'
                  : 'chatRequestTypePrivate'.tr(),
            ),
            isThreeLine: false,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _decline(request),
                  child: Text('chatRequestDecline'.tr()),
                ),
                FilledButton(
                  onPressed: () => _accept(request),
                  child: Text('chatRequestAccept'.tr()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
