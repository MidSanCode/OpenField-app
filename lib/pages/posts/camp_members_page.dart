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

  /// When set, this camp is a subgroup: the server only accepts members that
  /// already belong to the parent camp, so the add action picks from that
  /// roster instead of asking for a raw user id.
  final int? parentCampId;

  /// Parent camp's display name, for the picker's title.
  final String? parentCampName;

  const CampMembersPage({
    super.key,
    required this.campId,
    this.parentCampId,
    this.parentCampName,
  });

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
    // A subgroup only accepts people already in the parent camp, so offer that
    // roster rather than a free-form id: the id dialog would just collect a
    // 403 for anybody the parent does not know.
    final parentCampId = widget.parentCampId;
    if (parentCampId != null && parentCampId > 0) {
      await _addMemberFromParent(parentCampId);
      return;
    }
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

  /// Adds a member to a subgroup by picking from the parent camp's roster.
  ///
  /// The server enforces the same rule, so this mirrors it instead of
  /// repeating the failure: members already in the subgroup are filtered out,
  /// and an empty result says so rather than showing a blank sheet.
  Future<void> _addMemberFromParent(int parentCampId) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return;

    final List<CampMember> candidates;
    try {
      final (members, _) = await _api.listCampMembers(parentCampId, token);
      final existing = _members.map((m) => m.userId).toSet();
      candidates = members.where((m) => !existing.contains(m.userId)).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return;
    }
    if (!mounted) return;

    final parentName = widget.parentCampName ?? '';
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'campSubgroupPickMember'.tr(namedArgs: {'name': parentName}),
                style: Theme.of(ctx).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'campSubgroupPickEmpty'.tr(namedArgs: {'name': parentName}),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (_, index) {
                    final candidate = candidates[index];
                    return ListTile(
                      leading: Avatar(
                        radius: 18,
                        imageUrl: candidate.avatarUrl,
                        initials: candidate.displayName.isNotEmpty
                            ? candidate.displayName.characters.first
                            : '?',
                      ),
                      title: Text(candidate.displayName, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(ctx).pop(candidate.userId),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked <= 0) return;

    try {
      await _api.addCampMember(widget.campId, picked, token);
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
