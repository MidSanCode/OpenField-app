import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/camp.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/posts/posts_page.dart';

/// 贴吧-style camp directory: search, browse, join and create camps. Post
/// reading happens in the camp-scoped [PostsPage].
class CampsPage extends StatefulWidget {
  const CampsPage({super.key});

  @override
  State<CampsPage> createState() => _CampsPageState();
}

/// State for [CampsPage]: camp search and listing with an all/mine toggle,
/// join (direct-join camps only), create dialog and camp entry.
class _CampsPageState extends State<CampsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();
  List<Camp> _camps = [];
  bool _mine = false;
  bool _loading = true;
  String? _error;

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
      final camps = await _api.listCamps(auth.accessToken, query: _search.text.trim(), mine: _mine);
      if (mounted) {
        setState(() {
          _camps = camps;
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

  Future<void> _createCamp() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('loginWithOIDC'.tr())),
      );
      return;
    }
    final created = await showDialog<Camp>(
      context: context,
      builder: (_) => const _CreateCampDialog(),
    );
    if (created != null) {
      await _load();
    }
  }

  Future<void> _openCamp(Camp camp) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostsPage(campId: camp.id, campName: camp.name),
      ),
    );
    // Membership/post counts may have changed after visiting.
    _load();
  }

  Future<void> _joinCamp(Camp camp) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('loginWithOIDC'.tr())),
      );
      return;
    }
    try {
      await _api.joinCamp(camp.id, token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('campJoined'.tr())),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  /// Renames/redescribes a camp straight from the directory (owner/admin).
  Future<void> _editCamp(Camp camp) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditCampDialog(camp: camp, token: token),
    );
    if (updated == true) {
      await _load();
    }
  }

  /// Deletes a camp after an explicit confirmation. The server only allows the
  /// creator through, so the menu entry is restricted the same way.
  Future<void> _deleteCamp(Camp camp) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('campDeleteTitle'.tr()),
        content: Text('campDeleteBody'.tr(namedArgs: {'name': camp.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteCamp(camp.id, token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('campDeleted'.tr())),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('camps'.tr()),
        actions: [
          IconButton(
            icon: Icon(_mine ? Icons.public : Icons.person),
            tooltip: _mine ? 'campAll'.tr() : 'campMine'.tr(),
            onPressed: () {
              setState(() => _mine = !_mine);
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'campCreate'.tr(),
            onPressed: _createCamp,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'campSearchHint'.tr(),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
            ),
          ),
          Expanded(
            child: _loading
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
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _camps.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 120),
                                  Center(child: Text('campEmpty'.tr())),
                                ],
                              )
                            : ListView.builder(
                                itemCount: _camps.length,
                                itemBuilder: (context, index) {
                                  final camp = _camps[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        child: Text(
                                          camp.name.isNotEmpty ? camp.name.characters.first : '?',
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Flexible(child: Text(camp.name, overflow: TextOverflow.ellipsis)),
                                          const SizedBox(width: 6),
                                          if (camp.myRole == 'owner' || camp.myRole == 'admin') ...[
                                            _RoleChip(role: camp.myRole),
                                            const SizedBox(width: 6),
                                          ],
                                          Icon(
                                            camp.isVisible ? Icons.visibility : Icons.visibility_off,
                                            size: 14,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        '${camp.memberCount} ${'campMembers'.tr()} · ${camp.postCount} ${'campPosts'.tr()}'
                                        '${camp.description.isEmpty ? '' : '\n${camp.description}'}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      isThreeLine: camp.description.isNotEmpty,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (camp.isJoined)
                                            TextButton(
                                              onPressed: () => _openCamp(camp),
                                              child: Text('campEnter'.tr()),
                                            )
                                          else if (camp.directJoin)
                                            TextButton(
                                              onPressed: () => _joinCamp(camp),
                                              child: Text('groupJoin'.tr()),
                                            )
                                          else
                                            Text(
                                              'campInviteOnly'.tr(),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          // Owners/admins manage camps from
                                          // here; only the creator may delete.
                                          if (camp.canManage)
                                            PopupMenuButton<String>(
                                              tooltip: 'campSettings'.tr(),
                                              onSelected: (action) {
                                                if (action == 'edit') {
                                                  _editCamp(camp);
                                                } else if (action == 'delete') {
                                                  _deleteCamp(camp);
                                                }
                                              },
                                              itemBuilder: (menuContext) => [
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: ListTile(
                                                    dense: true,
                                                    contentPadding: EdgeInsets.zero,
                                                    leading: const Icon(Icons.edit_outlined),
                                                    title: Text('campEdit'.tr()),
                                                  ),
                                                ),
                                                if (camp.myRole == 'owner')
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: ListTile(
                                                      dense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                      leading: Icon(
                                                        Icons.delete_outline,
                                                        color: Theme.of(menuContext).colorScheme.error,
                                                      ),
                                                      title: Text(
                                                        'campDelete'.tr(),
                                                        style: TextStyle(
                                                          color: Theme.of(menuContext).colorScheme.error,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                        ],
                                      ),
                                      // Every camp row opens the camp feed so
                                      // the posts can be browsed; non-members
                                      // land on the join prompt inside.
                                      onTap: () => _openCamp(camp),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _CreateCampDialog extends StatefulWidget {
  const _CreateCampDialog();

  @override
  State<_CreateCampDialog> createState() => _CreateCampDialogState();
}

class _CreateCampDialogState extends State<_CreateCampDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  bool _isVisible = true;
  bool _directJoin = true;
  bool _memberPost = true;
  bool _memberPin = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final camp = await _api.createCamp(
        name,
        auth.accessToken!,
        description: _description.text.trim(),
        isVisible: _isVisible,
        directJoin: _directJoin,
        memberPost: _memberPost,
        memberPin: _memberPin,
      );
      if (mounted) {
        Navigator.of(context).pop(camp);
      }
    } catch (e) {
      if (mounted) {
        // Camp names are unique server-side; map the 409 to a friendly hint.
        final message = e.toString();
        setState(() {
          _error = message.contains('taken') ? 'campNameTaken'.tr() : message;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('campCreate'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(labelText: 'campName'.tr()),
            ),
            TextField(
              controller: _description,
              maxLength: 500,
              maxLines: 2,
              decoration: InputDecoration(labelText: 'campDescription'.tr()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('campVisible'.tr()),
              subtitle: Text('campVisibleHint'.tr(), style: Theme.of(context).textTheme.bodySmall),
              value: _isVisible,
              onChanged: (v) => setState(() => _isVisible = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('campDirectJoin'.tr()),
              subtitle: Text('campDirectJoinHint'.tr(), style: Theme.of(context).textTheme.bodySmall),
              value: _directJoin,
              onChanged: (v) => setState(() => _directJoin = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('campMemberPost'.tr()),
              subtitle: Text('campMemberPostHint'.tr(), style: Theme.of(context).textTheme.bodySmall),
              value: _memberPost,
              onChanged: (v) => setState(() => _memberPost = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('campMemberPin'.tr()),
              subtitle: Text('campMemberPinHint'.tr(), style: Theme.of(context).textTheme.bodySmall),
              value: _memberPin,
              onChanged: (v) => setState(() => _memberPin = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text('create'.tr()),
        ),
      ],
    );
  }
}

/// Dialog for editing a camp's basics (name + description) from the directory.
/// Deeper settings (visibility, join mode, permission switches) live in the
/// camp feed's settings sheet.
class _EditCampDialog extends StatefulWidget {
  const _EditCampDialog({required this.camp, required this.token});

  /// The camp being edited.
  final Camp camp;
  /// Caller access token used for the update call.
  final String token;

  @override
  State<_EditCampDialog> createState() => _EditCampDialogState();
}

class _EditCampDialogState extends State<_EditCampDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.camp.name);
    _description = TextEditingController(text: widget.camp.description);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'campName'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiService().updateCamp(
        widget.camp.id,
        widget.token,
        name: name != widget.camp.name ? name : null,
        description: _description.text.trim() != widget.camp.description
            ? _description.text.trim()
            : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e is ApiException && e.statusCode == 409
              ? 'campNameTaken'.tr()
              : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('campEdit'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'campNameLabel'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'campDescLabel'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
              : Text('save'.tr()),
        ),
      ],
    );
  }
}

/// Small badge marking the viewer's elevated role inside a camp row ("营主" /
/// "管理员"), so an owner immediately sees ownership instead of a join action.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  /// Camp role of the viewer: "owner" or "admin".
  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = role == 'owner';
    final bg = isOwner
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.secondaryContainer;
    final fg = isOwner
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOwner ? 'campRoleOwner'.tr() : 'campRoleAdmin'.tr(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
