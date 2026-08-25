import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/models/post_reply.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/pages/posts/post_detail_page.dart';
import 'package:openfield/widgets/post_card.dart';

/// The current user's favorited posts and replies, shown as two tabs.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  List<Post> _posts = [];
  List<PostReply> _replies = [];
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    final userId = auth.user?.id;
    if (token == null || userId == null) return;
    final isPosts = _tabController.index == 0;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (isPosts) {
        final posts = await _apiService.listFavoritePosts(token, userId);
        if (!mounted) return;
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      } else {
        final replies = await _apiService.listFavoriteReplies(token, userId);
        if (!mounted) return;
        setState(() {
          _replies = replies;
          _isLoading = false;
        });
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text('favorites'.tr()),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'favoritesPosts'.tr()),
            Tab(text: 'favoritesReplies'.tr()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPosts(),
          _buildReplies(),
        ],
      ),
    );
  }

  Widget _buildPosts() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _posts.isEmpty) {
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
    if (_posts.isEmpty) {
      return Center(child: Text('favoritesEmpty'.tr()));
    }
    return RefreshIndicator(
      onRefresh: _loadPostsOnly,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _posts.length,
        itemBuilder: (context, index) => PostCard(
          post: _posts[index],
          isMine: false,
          token: Provider.of<AuthService>(context).accessToken,
          onTapAuthor: () => _openAuthor(_posts[index].userId),
          onTapReply: () => _openPost(_posts[index]),
          onTap: () => _openPost(_posts[index]),
          onPostChanged: (updated) => setState(() {
            _posts = _posts.map((p) => p.id == updated.id ? updated : p).toList();
          }),
          onUnauthenticated: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('loginWithOIDC'.tr())),
            );
          },
        ),
      ),
    );
  }

  Future<void> _loadPostsOnly() async {
    if (_tabController.index == 0) {
      await _loadCurrentTab();
    }
  }

  Widget _buildReplies() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _replies.isEmpty) {
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
    if (_replies.isEmpty) {
      return Center(child: Text('favoritesEmpty'.tr()));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _replies.length,
      itemBuilder: (context, index) {
        final reply = _replies[index];
        return ListTile(
          leading: const Icon(Icons.insert_comment_outlined),
          title: Text(
            reply.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(reply.authorName),
          trailing: IconButton(
            icon: Icon(Icons.bookmark, color: Theme.of(context).colorScheme.primary),
            tooltip: 'removeFavorite'.tr(),
            onPressed: () async {
              final auth = Provider.of<AuthService>(context, listen: false);
              final token = auth.accessToken;
              if (token == null) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await _apiService.unfavoriteReply(reply.postId, reply.id, token);
                if (!mounted) return;
                setState(() {
                  _replies = _replies.where((r) => r.id != reply.id).toList();
                });
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PostDetailPage(post: Post(
                  id: reply.postId,
                  userId: reply.userId,
                  content: reply.parentContent ?? reply.content,
                  createdAt: reply.createdAt,
                  updatedAt: reply.updatedAt,
                )),
              ),
            );
          },
        );
      },
    );
  }

  void _openAuthor(int userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
    );
  }

  void _openPost(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
    );
  }
}