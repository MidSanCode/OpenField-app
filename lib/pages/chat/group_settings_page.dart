import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:openfield/data/models/chat_member.dart';
import 'package:openfield/data/models/conversation.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/e2ee_service.dart';
import 'package:openfield/pages/chat/start_chat_page.dart';
import 'package:openfield/widgets/verified_badge.dart';

/// Group chat settings (owner-managed): avatar/icon, name, public visibility,
/// direct join, end-to-end encryption, group-wide mute and the member list with
/// management actions. Opened from the conversation's top-right menu.
class GroupSettingsPage extends StatefulWidget {
  final Conversation conversation;

  const GroupSettingsPage({super.key, required this.conversation});

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  final ApiService _apiService = ApiService();
  late bool _isPublic;
  late bool _allowJoin;
  late bool _encrypted;
  late String _title;
  bool _saving = false;

  List<ChatMember> _members = [];
  bool _membersLoading = true;
  int _myUserId = 0;
  String _myRole = 'member';

  bool get _canManage => _myRole == 'owner' || _myRole == 'admin';
  bool get _isOwner => _myRole == 'owner';

  @override
  void initState() {
    super.initState();
    _isPublic = widget.conversation.isPublic;
    _allowJoin = widget.conversation.allowJoin;
    _encrypted = widget.conversation.encrypted;
    _title = widget.conversation.title;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      final detail = await _apiService.getConversation(token, widget.conversation.id);
      if (!mounted) return;
      setState(() {
        _members = detail.members;
        _myRole = detail.myMembership?.role ?? 'member';
        _myUserId = detail.myMembership?.userId ?? 0;
        _membersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _membersLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _saving = true);
    try {
      await _apiService.updateGroupSettings(
        token,
        widget.conversation.id,
        isPublic: _isPublic,
        allowJoin: _allowJoin,
        encrypted: _encrypted,
      );
      if (!mounted) return;
      if (_encrypted && !widget.conversation.encrypted) {
        await _enableEncryption(token);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('saved'.tr())));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Enabling E2EE for the first time: publish the owner's identity key, then
  /// generate a fresh group key and seal it to every member who has published
  /// a key. Members without one won't be able to decrypt new messages.
  Future<void> _enableEncryption(String token) async {
    try {
      await E2eeService.instance.ensureIdentity(_apiService, token);
    } catch (_) {
      // Identity publishing is best-effort; rotation below will still work if
      // the owner already has a local key.
    }
    final detail = await _apiService.getConversation(token, widget.conversation.id);
    final members = detail.members
        .where((m) => m.e2eePublicKey != null && m.e2eePublicKey!.isNotEmpty)
        .map((m) => (userId: m.userId, publicKey: m.e2eePublicKey!))
        .toList();
    if (members.isEmpty) {
      throw Exception('e2eeNoMemberKeys'.tr());
    }
    await E2eeService.instance.rotateGroupKey(
      _apiService,
      token,
      widget.conversation.id,
      members,
    );
  }

  // ---- Group name / avatar (owner only) ----

  Future<void> _renameGroup() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: _title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatGroupNickname'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(hintText: 'groupTitleHint'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || title == _title) return;
    try {
      await _apiService.updateGroupTitle(token, widget.conversation.id, title);
      if (!mounted) return;
      setState(() => _title = title);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('saved'.tr())));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _changeAvatar() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final picker = ImagePicker();
    final result = await picker.pickImage(source: ImageSource.gallery);
    if (result == null) return;
    try {
      final attachment =
          await _apiService.uploadAttachmentSmart(result.path, token, visibility: 'public');
      await _apiService.updateGroupAvatar(token, widget.conversation.id, attachment.url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('saved'.tr())));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ---- Member management ----

  Future<void> _inviteMember() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StartChatPage(inviteToGroup: widget.conversation.id),
      ),
    );
    if (mounted) _loadDetail();
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'chatOwnerRole'.tr();
      case 'admin':
        return 'chatAdminRole'.tr();
      default:
        return 'normalUser'.tr();
    }
  }

  Future<void> _showMemberActions(ChatMember member) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                backgroundImage: (member.avatarUrl != null && member.avatarUrl!.isNotEmpty)
                    ? NetworkImage(member.avatarUrl!)
                    : null,
                child: (member.avatarUrl == null || member.avatarUrl!.isEmpty)
                    ? Text(member.displayName.substring(0, 1).toUpperCase())
                    : null,
              ),
title: VerifiedName(
                name: member.displayName,
                verified: member.isVerified,
                memberLevel: member.memberLevel,
                memberActive: member.memberActive,
                nameColor: member.nameColor,
                nameColorTo: member.nameColorTo,
                nameDynamic: member.nameDynamic,
              ),
              subtitle: Text(_roleLabel(member.role)),
            ),
            const Divider(height: 1),
            if (member.isMuted)
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: Text('chatGroupUnmuteMember'.tr()),
                onTap: () => Navigator.of(ctx).pop('unmute'),
              )
            else
              ListTile(
                leading: const Icon(Icons.volume_off_outlined),
                title: Text('chatGroupMuteMember'.tr()),
                onTap: () => Navigator.of(ctx).pop('mute'),
              ),
            if (_isOwner && member.role == 'member')
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text('chatGroupSetAdmin'.tr()),
                onTap: () => Navigator.of(ctx).pop('set_admin'),
              ),
            if (_isOwner && member.role == 'admin')
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('chatGroupRemoveAdmin'.tr()),
                onTap: () => Navigator.of(ctx).pop('remove_admin'),
              ),
            if (_canManage && member.role != 'owner')
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text('chatGroupSetTitle'.tr()),
                subtitle: member.title.isNotEmpty
                    ? Text(member.title,
                        style: Theme.of(ctx).textTheme.bodySmall)
                    : null,
                onTap: () => Navigator.of(ctx).pop('set_title'),
              ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('chatGroupRemoveMember'.tr(),
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.of(ctx).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'mute':
        await _muteMember(member);
        break;
      case 'unmute':
        await _unmuteMember(member);
        break;
      case 'set_admin':
        await _setMemberRole(member, 'admin');
        break;
      case 'remove_admin':
        await _setMemberRole(member, 'member');
        break;
      case 'set_title':
        await _setMemberTitle(member);
        break;
      case 'remove':
        await _removeMember(member.userId);
        break;
    }
  }

  Future<void> _setMemberTitle(ChatMember member) async {
    final controller = TextEditingController(text: member.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatGroupSetTitle'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: InputDecoration(
            hintText: 'chatGroupTitleHint'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.setMemberTitle(
          token, widget.conversation.id, member.userId, result);
      if (!mounted) return;
      setState(() {
        _members = _members
            .map((m) => m.userId == member.userId
                ? ChatMember(
                    conversationId: m.conversationId,
                    userId: m.userId,
                    role: m.role,
                    note: m.note,
                    groupNickname: m.groupNickname,
                    title: result,
                    status: m.status,
                    addedBy: m.addedBy,
                    createdAt: m.createdAt,
                    mutedUntil: m.mutedUntil,
                    username: m.username,
                    nickname: m.nickname,
                    avatarUrl: m.avatarUrl,
                    isVerified: m.isVerified,
                    e2eePublicKey: m.e2eePublicKey,
                  )
                : m)
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _removeMember(int userId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.removeGroupMember(token, widget.conversation.id, userId);
      if (!mounted) return;
      setState(() {
        _members = _members.where((m) => m.userId != userId).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _muteMember(ChatMember member) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final minutes = await _pickMuteDuration();
    if (minutes == null) return;
    try {
      await _apiService.muteMember(token, widget.conversation.id, member.userId, minutes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('chatGroupMemberMutedAction'.tr())));
      _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _unmuteMember(ChatMember member) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.unmuteMember(token, widget.conversation.id, member.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('chatGroupMemberUnmutedAction'.tr())));
      _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _setMemberRole(ChatMember member, String role) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.setMemberRole(token, widget.conversation.id, member.userId, role);
      if (!mounted) return;
      _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Lets the caller pick a mute duration. Returns null when cancelled.
  Future<int?> _pickMuteDuration() async {
    const presets = <String, int>{
      'chatGroupMute1Hour': 60,
      'chatGroupMute6Hours': 360,
      'chatGroupMute12Hours': 720,
      'chatGroupMute1Day': 1440,
      'chatGroupMute1Week': 10080,
      'chatGroupMuteForever': 5256000,
    };
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('chatGroupMuteMember'.tr(),
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final entry in presets.entries)
              ListTile(
                title: Text(entry.key.tr()),
                onTap: () => Navigator.of(ctx).pop(entry.value.toString()),
              ),
            ListTile(
              title: Text('chatGroupMuteCustom'.tr()),
              onTap: () => Navigator.of(ctx).pop('custom'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return null;
    if (choice != 'custom') return int.parse(choice);
    if (!mounted) return null;
    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatGroupMuteCustom'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'chatGroupMuteMinutes'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(controller.text.trim())),
            child: Text('ok'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes == null || minutes <= 0) return null;
    return minutes;
  }

  Future<void> _muteAll() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final minutes = await _pickDuration();
    if (minutes == null) return;
    try {
      await _apiService.muteAllMembers(token, widget.conversation.id, minutes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('chatGroupMuteAllAction'.tr())));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _unmuteAll() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.unmuteAllMembers(token, widget.conversation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('chatGroupUnmuteAllAction'.tr())));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<int?> _pickDuration() async {
    const presets = <String, int>{
      'chatGroupMute1Hour': 60,
      'chatGroupMute6Hours': 360,
      'chatGroupMute12Hours': 720,
      'chatGroupMute1Day': 1440,
      'chatGroupMute1Week': 10080,
      'chatGroupMuteForever': 5256000,
    };
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('chatGroupMuteAllAction'.tr(),
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final entry in presets.entries)
              ListTile(
                title: Text(entry.key.tr()),
                onTap: () => Navigator.of(ctx).pop(entry.value.toString()),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return null;
    return int.parse(choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMuted = widget.conversation.isGroupMuted;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_isOwner)
            TextButton(
              onPressed: _saving ? null : _saveSettings,
              child: Text('save'.tr()),
            ),
        ],
      ),
      body: _membersLoading && _members.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildHeader(theme),
                const Divider(height: 1),
                if (_isOwner) ...[
                  SwitchListTile(
                    value: _isPublic,
                    title: Text('chatGroupIsPublic'.tr()),
                    subtitle: Text('chatGroupIsPublicHint'.tr()),
                    onChanged: _saving
                        ? null
                        : (v) => setState(() {
                              _isPublic = v;
                              if (!v) _allowJoin = false;
                            }),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _allowJoin,
                    title: Text('chatGroupAllowJoin'.tr()),
                    subtitle: Text('chatGroupAllowJoinHint'.tr()),
                    onChanged: _saving || !_isPublic
                        ? null
                        : (v) => setState(() => _allowJoin = v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _encrypted,
                    title: Text('chatGroupEncrypted'.tr()),
                    subtitle: Text('chatGroupEncryptedHint'.tr()),
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _encrypted = v),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('chatGroupMuteDuration'.tr(),
                        style: theme.textTheme.titleMedium),
                  ),
                  if (isMuted)
                    ListTile(
                      leading: const Icon(Icons.volume_off_outlined),
                      title: Text('chatGroupMutedBanner'.tr()),
                      trailing: TextButton(
                        onPressed: _unmuteAll,
                        child: Text('chatGroupUnmuteAllAction'.tr()),
                      ),
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.volume_off_outlined),
                      title: Text('chatGroupMuteAllAction'.tr()),
                      subtitle: Text('chatGroupMuteAllHint'.tr()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _muteAll,
                    ),
                  const Divider(height: 1),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      Text('chatGroupMembers'.tr(),
                          style: theme.textTheme.titleMedium),
                      const Spacer(),
                      if (_canManage)
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_outlined),
                          tooltip: 'chatGroupInvite'.tr(),
                          onPressed: _inviteMember,
                        ),
                    ],
                  ),
                ),
                _buildMembersList(),
              ],
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final avatarUrl = widget.conversation.avatarUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage:
                    avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Icon(Icons.group,
                        size: 32, color: theme.colorScheme.onPrimaryContainer)
                    : null,
              ),
              if (_isOwner)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Material(
                    shape: const CircleBorder(),
                    color: theme.colorScheme.primary,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _changeAvatar,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.photo_camera,
                            size: 16, color: theme.colorScheme.onPrimary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'chatGroupMemberCount'.tr(namedArgs: {
                    'count': '${_members.length}',
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_isOwner) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _renameGroup,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text('chatGroupRename'.tr()),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersList() {
    if (_membersLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final members =
        _members.where((m) => m.userId != _myUserId).toList();
    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('chatGroupNoMembers'.tr(),
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return Column(
      children: [
        for (final m in members)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: (m.avatarUrl != null && m.avatarUrl!.isNotEmpty)
                  ? NetworkImage(m.avatarUrl!)
                  : null,
              child: (m.avatarUrl == null || m.avatarUrl!.isEmpty)
                  ? Text(m.displayName.substring(0, 1).toUpperCase())
                  : null,
            ),
title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: VerifiedName(
                    name: m.displayName,
                    verified: m.isVerified,
                    memberLevel: m.memberLevel,
                    memberActive: m.memberActive,
                    nameColor: m.nameColor,
                    nameColorTo: m.nameColorTo,
                    nameDynamic: m.nameDynamic,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (m.isMuted) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.volume_off_outlined,
                      size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ],
            ),
            subtitle: Text(_roleLabel(m.role)),
            trailing: _canManage && m.role != 'owner'
                ? IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'chatGroupMemberActions'.tr(),
                    onPressed: () => _showMemberActions(m),
                  )
                : null,
          ),
      ],
    );
  }
}

