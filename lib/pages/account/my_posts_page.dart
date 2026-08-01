import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
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
      final posts = await _apiService.getPostsByUser(widget.userId, token);
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
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePostConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$l10n.loadFailed (${_error.toString()})',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    } else if (_posts == null || _posts!.isEmpty) {
      body = Center(
        child: Text(l10n.noPosts, style: theme.textTheme.bodyMedium),
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
          );        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myPosts)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: body,
      ),
    );
  }
}
