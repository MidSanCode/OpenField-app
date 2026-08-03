import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';

/// Lets the user search for another user to start a private chat with, or
/// (when [inviteToGroup] is set) invite them into a group conversation.
class StartChatPage extends StatefulWidget {
  final int? inviteToGroup;

  const StartChatPage({super.key, this.inviteToGroup});

  @override
  State<StartChatPage> createState() => _StartChatPageState();
}

class _StartChatPageState extends State<StartChatPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  List<User> _users = [];
  bool _isLoading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    final q = query.trim();
    if (token == null || q.isEmpty) {
      if (mounted) {
        setState(() {
          _users = [];
          _searched = false;
          _isLoading = false;
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _searched = true;
      _error = null;
    });
    try {
      final users = await _apiService.searchUsers(token, q);
      if (!mounted) return;
      setState(() {
        _users = users.where((u) => u.id != authService.user?.id).toList();
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

  Future<void> _onUserTap(User user) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      if (widget.inviteToGroup != null) {
        await _apiService.inviteToGroup(token, widget.inviteToGroup!, user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('chatInviteSent'.tr())),
          );
          Navigator.of(context).pop();
        }
      } else {
        await _apiService.startPrivateChat(token, user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('chatRequestSent'.tr())),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('chatSearchUsers'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'chatSearchHint'.tr(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _queryController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _queryController.clear();
                          _onQueryChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('loadFailed'.tr()),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _search(_queryController.text),
              child: Text('retry'.tr()),
            ),
          ],
        ),
      );
    }
    if (!_searched) {
      return Center(
        child: Text(
          'chatSearchHint'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(child: Text('chatNoUsers'.tr()));
    }
    return ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final user = _users[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: user.avatarUrl.isNotEmpty ? NetworkImage(user.avatarUrl) : null,
            child: user.avatarUrl.isEmpty
                ? Icon(Icons.person, color: Theme.of(context).colorScheme.onPrimaryContainer)
                : null,
          ),
          title: Text(user.displayName),
          subtitle: user.username.isNotEmpty && user.username != user.displayName
              ? Text('@${user.username}')
              : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _onUserTap(user),
        );
      },
    );
  }
}
