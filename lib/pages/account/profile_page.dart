import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/posts/post_detail_page.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/post_card.dart';
import 'package:openfield/widgets/verified_badge.dart';

/// Public profile of any user: banner, avatar, nickname, @username, bio,
/// verified badge, and their posts.
class ProfilePage extends StatefulWidget {
  final int userId;

  const ProfilePage({super.key, required this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ApiService _apiService = ApiService();
  User? _user;
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
      final user = await _apiService.getUser(token, widget.userId);
      final posts = await _apiService.getPostsByUser(widget.userId, token);
      if (mounted) {
        setState(() {
          _user = user;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null || _user == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$l10n.loadFailed (${_error?.toString() ?? 'not found'})',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    } else {
      final user = _user!;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            _buildHeader(context, theme, user, l10n),
            if (user.bio.isNotEmpty) ...[
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: MarkdownContent(data: user.bio),
              ),
            ],
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                l10n.posts,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_posts == null || _posts!.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(l10n.noPosts, style: theme.textTheme.bodyMedium),
                ),
              )
            else
              for (final post in _posts!)
                PostCard(
                  post: post,
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
                ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('@${_user?.username ?? ''}')),
      body: body,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    User user,
    AppLocalizations l10n,
  ) {
    final hasBanner = user.bannerUrl.isNotEmpty;
    final hasAvatar = user.avatarUrl.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: 160,
          width: double.infinity,
          child: hasBanner
              ? Image.network(
                  user.bannerUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: theme.colorScheme.primaryContainer,
                  ),
                )
              : Container(color: theme.colorScheme.primaryContainer),
        ),
        Positioned(
          left: 24,
          bottom: -44,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.surface, width: 3),
            ),
            child: CircleAvatar(
              radius: 44,
              backgroundColor: theme.colorScheme.surface,
              backgroundImage: hasAvatar ? NetworkImage(user.avatarUrl) : null,
              child: hasAvatar
                  ? null
                  : Icon(Icons.person, size: 44, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        Positioned(
          right: 0,
          left: 0,
          top: 168,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: VerifiedName(
                        name: user.displayName,
                        verified: user.isVerified,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '@${user.username}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (user.role == 'admin') ...[
                  const SizedBox(height: 6),
                  Chip(
                    avatar: const Icon(Icons.admin_panel_settings, size: 16),
                    label: Text(l10n.admin),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
