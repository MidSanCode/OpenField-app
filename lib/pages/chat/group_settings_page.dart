import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:openfield/data/models/conversation.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// Group settings editor (owner-only). Lets the owner toggle whether the group
/// is publicly discoverable and whether anyone can join directly, plus
/// group-wide mute controls.
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isPublic = widget.conversation.isPublic;
    _allowJoin = widget.conversation.allowJoin;
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
      );
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
      'chatMute1Hour': 60,
      'chatMute6Hours': 360,
      'chatMute12Hours': 720,
      'chatMute1Day': 1440,
      'chatMute1Week': 10080,
      'chatMuteForever': 5256000,
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
        title: Text('chatGroupSettings'.tr()),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveSettings,
            child: Text('save'.tr()),
          ),
        ],
      ),
      body: ListView(
        children: [
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
        ],
      ),
    );
  }
}
