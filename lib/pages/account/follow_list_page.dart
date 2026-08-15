import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/widgets/verified_badge.dart';

enum FollowListType { followers, following, friends }

class FollowListPage extends StatefulWidget {
  final int userId;
  final FollowListType initialTab;

  const FollowListPage({
    super.key,
    required this.userId,
    this.initialTab = FollowListType.followers,
  });

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  List<User> _followers = [];
  List<User> _following = [];
  List<User> _friends = [];
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: switch (widget.initialTab) {
        FollowListType.following => 1,
        FollowListType.friends => 2,
        FollowListType.followers => 0,
      },
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
    final index = _tabController.index.ceil().toInt();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final List<User> users;
      switch (index) {
        case 0:
          users = await _apiService.listFollowers(widget.userId, token: token);
        case 1:
          users = await _apiService.listFollowing(widget.userId, token: token);
        default:
          users = await _apiService.listFriends(widget.userId, token: token);
      }
      if (!mounted) return;
      setState(() {
        switch (index) {
          case 0:
            _followers = users;
          case 1:
            _following = users;
          default:
            _friends = users;
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
    final index = _tabController.index.ceil().toInt();
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (index) {
          0 => 'followers'.tr(),
          1 => 'following'.tr(),
          _ => 'friends'.tr(),
        }),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'followers'.tr()),
            Tab(text: 'following'.tr()),
            Tab(text: 'friends'.tr()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserList(_followers, emptyText: 'noPosts'.tr()),
          _buildUserList(_following, emptyText: 'noPosts'.tr()),
          _buildUserList(_friends, emptyText: 'friendsEmpty'.tr()),
        ],
      ),
    );
  }

  Widget _buildUserList(List<User> users, {String? emptyText}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('loadFailed'.tr(), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadCurrentTab, child: Text('retry'.tr())),
          ],
        ),
      );
    }
    if (users.isEmpty) {
      return Center(child: Text(emptyText ?? 'noPosts'.tr()));
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