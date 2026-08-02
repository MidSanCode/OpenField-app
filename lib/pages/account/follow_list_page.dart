import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/widgets/verified_badge.dart';

enum FollowListType { followers, following }

class FollowListPage extends StatefulWidget {
  final int userId;
  final FollowListType initialTab;

  const FollowListPage({super.key, required this.userId, this.initialTab = FollowListType.followers});

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  List<User> _followers = [];
  List<User> _following = [];
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == FollowListType.following ? 1 : 0,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadCurrentTab();
    });
    _loadCurrentTab();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentTab() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    final isFollowers =
        _tabController.animation?.value == 0.0;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final users = isFollowers
          ? await _apiService.listFollowers(widget.userId, token: token)
          : await _apiService.listFollowing(widget.userId, token: token);
      if (!mounted) return;
      setState(() {
        if (isFollowers) {
          _followers = users;
        } else {
          _following = users;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabController.animation?.value == 0.0 ? l10n.followers : l10n.following),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.followers),
            Tab(text: l10n.following),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserList(_followers, l10n),
          _buildUserList(_following, l10n),
        ],
      ),
    );
  }

  Widget _buildUserList(List<User> users, AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.loadFailed, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadCurrentTab, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (users.isEmpty) {
      return Center(
        child: Text(l10n.noPosts),
      );
    }
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) => _buildUserRow(users[index]),
    );
  }

  Widget _buildUserRow(User user) {
    final hasAvatar = user.avatarUrl.isNotEmpty;
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: hasAvatar ? NetworkImage(user.avatarUrl) : null,
        child: hasAvatar
            ? null
            : Text(user.username.isNotEmpty ? user.username[0].toUpperCase() : '?'),
      ),
      title: VerifiedName(
        name: user.displayName,
        verified: user.isVerified,
      ),
      subtitle: Text('@${user.username}'),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProfilePage(userId: user.id)),
        );
      },
    );
  }
}