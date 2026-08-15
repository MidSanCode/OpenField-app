import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/pages/posts/post_detail_page.dart';
import 'package:openfield/widgets/post_card.dart';

class MyPostsPage extends StatefulWidget {
  final int userId;

  const MyPostsPage({super.key, required this.userId});

  @override
  State<MyPostsPage> createState() => _MyPostsPageState();
}

class _MyPostsPageState extends State<MyPostsPage> {
  final ApiService _apiService = ApiService();
  List<Post>? _posts;
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final token = auth.accessToken;
      if (token == null) {
        setState(() => _error = 'Not authenticated');
        return;
      }
      final posts = await _apiService.getPostsByUser(widget.userId, token: token);
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _deletePost(Post post) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('deletePostConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await _apiService.deletePost(post.id, authService.accessToken!);
      await _load();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${'loadFailed'.tr()} (${_error.toString()})',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text('retry'.tr())),
          ],
        ),
      );
    } else if (_posts == null || _posts!.isEmpty) {
      body = Center(
        child: Text('noPosts'.tr(), style: theme.textTheme.bodyMedium),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _posts!.length,
        itemBuilder: (context, index) {
          final post = _posts![index];
          return PostCard(
            post: post,
            isMine: true,
            token: Provider.of<AuthService>(context).accessToken,
            onPostChanged: (updated) => setState(() {
              _posts = _posts!.map((p) => p.id == updated.id ? updated : p).toList();
            }),
            onUnauthenticated: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('loginWithOIDC'.tr())),
              );
            },
            onDelete: () => _deletePost(post),
            onTapAuthor: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfilePage(userId: post.userId)),
              );
            },
            onTapReply: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
              );
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('myPosts'.tr())),
      body: RefreshIndicator(
        onRefresh: _load,
        child: body,
      ),
    );
  }
}
