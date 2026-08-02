import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/account/follow_list_page.dart';
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
  bool _followLoading = false;

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
      final user = await _apiService.getUser(widget.userId, token: token);
      final posts = await _apiService.getPostsByUser(widget.userId, token: token);
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
                  token: Provider.of<AuthService>(context, listen: false).accessToken,
                  onPostChanged: (updated) {
                    setState(() {
                      _posts = _posts!.map((p) => p.id == updated.id ? updated : p).toList();
                    });
                  },
                  onUnauthenticated: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(context)!.loginWithOIDC)),
                    );
                  },
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
      appBar: AppBar(
        title: Text(_user?.displayName ?? ''),
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        // Centered avatar stacked below banner
        const SizedBox(height: 16),
        Center(
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
        const SizedBox(height: 12),
        // Nickname (falls back to username in displayName)
        Center(
          child: VerifiedName(
            name: user.displayName,
            verified: user.isVerified,
            style: theme.textTheme.titleLarge,
          ),
        ),
        if (user.isVerified && user.verifiedBy.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: Chip(
              avatar: const Icon(Icons.verified, size: 16, color: Colors.lightBlue),
              label: Text(user.verifiedBy),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          ),
        ],
        if (user.isVerified && user.verifiedNote.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              user.verifiedNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        // Username
        Center(
          child: Text(
            '@${user.username}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Follow counts row
        _buildFollowCountsRow(theme, user, l10n),
        const SizedBox(height: 8),
        _buildFollowButton(theme, user, l10n),
        if (user.role == 'admin') ...[
          const SizedBox(height: 8),
          Center(
            child: Chip(
              avatar: const Icon(Icons.admin_panel_settings, size: 16),
              label: Text(l10n.admin),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFollowCountsRow(ThemeData theme, User user, AppLocalizations l10n) {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: () => _openFollowList(FollowListType.followers),
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '${user.followerCount}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' ${l10n.followers}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        InkWell(
          onTap: () => _openFollowList(FollowListType.following),
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '${user.followingCount}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' ${l10n.following}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFollowButton(ThemeData theme, User user, AppLocalizations l10n) {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null) return const SizedBox.shrink();
    final isSelf = auth.user?.id == user.id;
    if (isSelf) return const SizedBox.shrink();

    if (user.isFollowing) {
      return Center(
        child: OutlinedButton(
          onPressed: _followLoading ? null : () => _toggleFollow(false),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(140, 36),
            side: BorderSide(color: theme.colorScheme.outline),
          ),
          child: _followLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.unfollow),
        ),
      );
    }

    return Center(
      child: FilledButton(
        onPressed: _followLoading ? null : () => _toggleFollow(true),
        style: FilledButton.styleFrom(minimumSize: const Size(140, 36)),
        child: _followLoading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(l10n.follow),
      ),
    );
  }

  Future<void> _toggleFollow(bool follow) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;

    final followerDelta = follow ? 1 : -1;
    setState(() {
      _followLoading = true;
      _user = _user!.copyWith(
        isFollowing: follow,
        followerCount: _user!.followerCount + followerDelta,
      );
    });

    try {
      if (follow) {
        await _apiService.followUser(widget.userId, token);
      } else {
        await _apiService.unfollowUser(widget.userId, token);
      }
    } catch (e) {
      setState(() {
        _user = _user!.copyWith(
          isFollowing: !follow,
          followerCount: _user!.followerCount - followerDelta,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  void _openFollowList(FollowListType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowListPage(userId: widget.userId, initialTab: type),
      ),
    );
  }
}
