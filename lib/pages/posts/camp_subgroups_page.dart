import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/camp.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/posts/posts_page.dart';

/// Lists a camp's subgroups (子群) and lets the camp's owner/admins create
/// one. Subgroups are private by construction: they never appear in the camp
/// directory and only members of the parent camp can open them, so this page
/// is reached from inside the parent camp.
class CampSubgroupsPage extends StatefulWidget {
  /// The parent camp whose subgroups are listed.
  final int parentCampId;

  /// Parent camp display name, shown in the header.
  final String parentCampName;

  /// Whether the viewer may create subgroups (owner/admin of the parent).
  final bool canManage;

  const CampSubgroupsPage({
    super.key,
    required this.parentCampId,
    required this.parentCampName,
    required this.canManage,
  });

  @override
  State<CampSubgroupsPage> createState() => _CampSubgroupsPageState();
}

class _CampSubgroupsPageState extends State<CampSubgroupsPage> {
  final ApiService _api = ApiService();
  List<Camp> _subgroups = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final subs = await _api.listSubgroups(widget.parentCampId, token: auth.accessToken);
      if (mounted) {
        setState(() {
          _subgroups = subs;
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

  Future<void> _createSubgroup() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('loginWithOIDC'.tr())));
      return;
    }
    final created = await showDialog<Camp>(
      context: context,
      builder: (_) => _CreateSubgroupDialog(parentCampId: widget.parentCampId),
    );
    if (created != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('campSubgroupCreated'.tr())));
      }
      await _load();
    }
  }

  Future<void> _openSubgroup(Camp subgroup) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostsPage(campId: subgroup.id, campName: subgroup.name),
      ),
    );
    // The roster may have grown while the subgroup was open.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('campSubgroups'.tr()),
        actions: [
          if (widget.canManage)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'campCreateSubgroup'.tr(),
              onPressed: _createSubgroup,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: Text('retry'.tr())),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  // The parent name plus the privacy rule, so an admin
                  // reading this page understands why the list is short
                  // and who can be let in.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.parentCampName,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'campSubgroupsHint'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_subgroups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            widget.canManage
                                ? 'campSubgroupsEmptyManage'.tr()
                                : 'campSubgroupsEmpty'.tr(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._subgroups.map(
                      (sub) => ListTile(
                        leading: const Icon(Icons.forum_outlined),
                        title: Text(sub.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          sub.description.isEmpty
                              ? 'campSubgroupsMembers'.tr(
                                  namedArgs: {'count': '${sub.memberCount}'},
                                )
                              : sub.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openSubgroup(sub),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Create-subgroup form: a name and an optional description. Visibility and
/// join switches are deliberately absent — the server forces a subgroup to be
/// private and non-joinable.
class _CreateSubgroupDialog extends StatefulWidget {
  final int parentCampId;

  const _CreateSubgroupDialog({required this.parentCampId});

  @override
  State<_CreateSubgroupDialog> createState() => _CreateSubgroupDialogState();
}

class _CreateSubgroupDialogState extends State<_CreateSubgroupDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_submitting && _name.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('loginWithOIDC'.tr())));
      return;
    }
    setState(() => _submitting = true);
    try {
      final camp = await _api.createSubgroup(
        widget.parentCampId,
        _name.text.trim(),
        token,
        description: _description.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(camp);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('campCreateSubgroup'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'campName'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          TextField(
            controller: _description,
            maxLength: 500,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              labelText: 'campDescription'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          Text(
            'campSubgroupsHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('create'.tr()),
        ),
      ],
    );
  }
}
