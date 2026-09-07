import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/camp.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/settings_service.dart';

/// App announcements: startup history for everyone; admins publish new
/// notices and retire old ones (needs the app.announcements.manage
/// permission, surfaced by the server as any permission the user holds).
class AppAnnouncementPage extends StatefulWidget {
  const AppAnnouncementPage({super.key});

  @override
  State<AppAnnouncementPage> createState() => _AppAnnouncementPageState();
}

/// State for [AppAnnouncementPage]: probes the manage permission to decide
/// whether the composer shows, loads the announcement list and publishes /
/// retires notices for admins.
class _AppAnnouncementPageState extends State<AppAnnouncementPage> {
  final ApiService _api = ApiService();
  List<AppAnnouncement> _items = [];
  bool _loading = true;
  String? _error;
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final token = auth.accessToken;
      // Admin capability probe: the manage permission turns on the composer
      // and retires/activates controls. Failure simply means a normal user.
      if (token != null && token.isNotEmpty) {
        try {
          final perms = await _api.getMyPermissions(token);
          final list = perms['permissions'];
          if (list is List) {
            final isAdmin = list.any((p) => p.toString() == 'app.announcements.manage');
            if (mounted && isAdmin != _admin) setState(() => _admin = isAdmin);
          }
        } catch (_) {}
      }
      // Admins get the full history (including retired entries); regular
      // users see the active list. Permission probing is implicit: with the
      // manage permission the ?all=1 query succeeds, otherwise the server
      // still returns the active-only view.
      final items = await _api.listAppAnnouncements(token: token, all: _admin);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final content = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final token = Provider.of<AuthService>(context, listen: false).accessToken!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('announcementNew'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, maxLength: 200, decoration: InputDecoration(labelText: 'announcementTitle'.tr())),
            TextField(controller: content, maxLines: 5, maxLength: 10000, decoration: InputDecoration(labelText: 'announcementBody'.tr())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('send'.tr())),
        ],
      ),
    );
    if (ok != true || content.text.trim().isEmpty) return;
    try {
      await _api.createAppAnnouncement(title.text.trim(), content.text.trim(), token);
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggle(AppAnnouncement ann) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).accessToken!;
      await _api.setAnnouncementActive(ann.id, !ann.active, token);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('announcementHistory'.tr()),
        actions: [
          if (_admin)
            IconButton(icon: const Icon(Icons.add), tooltip: 'announcementNew'.tr(), onPressed: _create),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('loadFailed'.tr()),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text('retry'.tr())),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(child: Text('announcementEmpty'.tr()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ann = _items[index];
                          final dismissed = context
                              .read<SettingsService>()
                              .dismissedAnnouncementIds
                              .contains(ann.id);
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                ann.active ? Icons.campaign_outlined : Icons.archive_outlined,
                                color: ann.active ? theme.colorScheme.primary : null,
                              ),
                              title: Text(ann.title),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  ann.content,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              isThreeLine: true,
                              trailing: _admin
                                  ? IconButton(
                                      tooltip: ann.active
                                          ? 'announcementRetire'.tr()
                                          : 'announcementActivate'.tr(),
                                      icon: Icon(ann.active
                                          ? Icons.archive_outlined
                                          : Icons.unarchive_outlined),
                                      onPressed: () => _toggle(ann),
                                    )
                                  : (dismissed
                                      ? TextButton(
                                          onPressed: () async {
                                            await context
                                                .read<SettingsService>()
                                                .dismissAnnouncement(ann.id)
                                                .then((_) => setState(() {}));
                                          },
                                          child: Text('announcementDontShow'.tr()),
                                        )
                                      : null),
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(ann.title),
                                    content: SingleChildScrollView(child: Text(ann.content)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: Text('close'.tr()),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
