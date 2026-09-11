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
                                      trailing: camp.isMember
                                          ? TextButton(
                                              onPressed: () => _openCamp(camp),
                                              child: Text('campEnter'.tr()),
                                            )
                                          : (camp.directJoin
                                              ? TextButton(
                                                  onPressed: () => _joinCamp(camp),
                                                  child: Text('groupJoin'.tr()),
                                                )
                                              : Text(
                                                  'campInviteOnly'.tr(),
                                                  style: theme.textTheme.bodySmall,
                                                )),
                                      onTap: camp.isMember ? () => _openCamp(camp) : null,
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
