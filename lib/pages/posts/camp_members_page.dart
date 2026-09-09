import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:openfield/data/models/camp.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// Camp member management: roster with roles, kick, role changes and
/// direct enrollment. Roster visibility is member-only server-side; the
/// mutation controls appear per the caller's role.
class CampMembersPage extends StatefulWidget {
  final int campId;

  const CampMembersPage({super.key, required this.campId});

  @override
  State<CampMembersPage> createState() => _CampMembersPageState();
}

class _CampMembersPageState extends State<CampMembersPage> {
  final ApiService _api = ApiService();
  List<CampMember> _members = [];
  String _myRole = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'loginWithOIDC'.tr();
          _loading = false;
        });
      }
      return;
    }
    try {
      final (members, myRole) = await _api.listCampMembers(widget.campId, token);
      if (mounted) {
        setState(() {
          _members = members;
          _myRole = myRole;
          _loading = false;
          _error = null;
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

  bool get _isOwner => _myRole == 'owner';
  bool get _isAdmin => _isOwner || _myRole == 'admin';

  Future<void> _changeRole(CampMember member, String role) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    try {
      await _api.setCampMemberRole(widget.campId, member.userId, role, token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('campRoleChanged'.tr())),
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

  Future<void> _kick(CampMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('campKickTitle'.tr()),
        content: Text('campKickBody'.tr(namedArgs: {'name': member.displayName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    try {
      await _api.removeCampMember(widget.campId, member.userId, token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('campMemberKicked'.tr())),
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

  Future<void> _addMember() async {
    final controller = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('campAddMember'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'campAddMemberHint'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim()) != null && int.parse(controller.text.trim()) > 0),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
    if (added != true) return;
    final userId = int.tryParse(controller.text.trim()) ?? 0;
    if (userId <= 0) return;
    if (!mounted) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    try {
      await _api.addCampMember(widget.campId, userId, token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('campMemberAdded'.tr())),
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
        title: Text('campMembersTitle'.tr()),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'campAddMember'.tr(),
              onPressed: _addMember,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text('retry'.tr())),
                    ],
                  ),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _members.isEmpty
                      ? ListView(children: [const SizedBox(height: 120), Center(child: Text('campMembersEmpty'.tr()))])
                      : ListView.builder(
                          itemCount: _members.length,
                          itemBuilder: (context, index) {
                            final member = _members[index];
                            final isTargetOwner = member.role == 'owner';
                            final isTargetAdmin = member.role == 'admin';
                            return ListTile(
                              leading: Avatar(radius: 18, imageUrl: member.avatarUrl, initials: member.displayName.isNotEmpty ? member.displayName.characters.first : '?'),
                              title: Text(member.displayName, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                member.role == 'owner'
                                    ? 'campRoleOwner'.tr()
                                    : isTargetAdmin
                                        ? 'campRoleAdmin'.tr()
                                        : 'campRoleMember'.tr(),
                              ),
                              trailing: _memberActions(member, isTargetOwner, isTargetAdmin, theme),
                            );
                          },
                        ),
                ),
    );
  }

  Widget? _memberActions(CampMember member, bool isTargetOwner, bool isTargetAdmin, ThemeData theme) {
    if (isTargetOwner) return null;
    final controls = <Widget>[];
    if (_isOwner) {
      controls.add(
        TextButton(
          onPressed: () => _changeRole(member, isTargetAdmin ? 'member' : 'admin'),
          child: Text(isTargetAdmin ? 'campDemote'.tr() : 'campPromote'.tr()),
        ),
      );
    }
    if (_isAdmin && (!isTargetAdmin || _isOwner)) {
      controls.add(
        IconButton(
          icon: Icon(Icons.person_remove_outlined, color: theme.colorScheme.error),
          tooltip: 'campKick'.tr(),
          onPressed: () => _kick(member),
        ),
      );
    }
    if (controls.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: controls);
  }
}
