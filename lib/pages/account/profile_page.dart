import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/media_image.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/account/follow_list_page.dart';
import 'package:openfield/pages/posts/post_detail_page.dart';
import 'package:openfield/widgets/experience_bar.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/post_card.dart';
import 'package:openfield/widgets/verified_badge.dart';

/// Public profile of any user: banner, avatar, nickname, @username, bio,
/// and verified badge.
class ProfilePage extends StatefulWidget {
  final int userId;

  const ProfilePage({super.key, required this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ApiService _apiService = ApiService();
  User? _user;
  Object? _error;
  bool _isLoading = true;
  bool _followLoading = false;
  List<Post> _posts = [];
  bool _postsLoading = false;

  Future<void> _loadPosts(String? token) async {
    if (mounted) setState(() => _postsLoading = true);
    try {
      final posts =
          await _apiService.getPostsByUser(widget.userId, token: token);
      if (mounted) {
        setState(() {
          _posts = posts;
          _postsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  String _formatLastSeen(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${t.year}-${t.month}-${t.day}';
  }

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
      if (mounted) {
        setState(() {
          _user = user;
          _isLoading = false;
        });
        _loadPosts(token);
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
    final theme = Theme.of(context);

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null || _user == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${'loadFailed'.tr()} (${_error?.toString() ?? 'not found'})',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text('retry'.tr())),
          ],
        ),
      );
    } else {
      final user = _user!;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            _buildHeader(context, theme, user),
            if (user.bio.isNotEmpty) ...[
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: MarkdownContent(data: user.bio),
              ),
            ],
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('myPosts'.tr(),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            if (_postsLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_posts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('noPosts'.tr())),
              )
            else
              for (final post in _posts)
                PostCard(
                  post: post,
                  isMine: post.userId == user.id,
                  token: Provider.of<AuthService>(context, listen: false)
                      .accessToken,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => PostDetailPage(post: post)),
                  ),
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
              ? MediaImage(
                  url: user.bannerUrl,
                  fit: BoxFit.cover,
                )
              : Container(color: theme.colorScheme.primaryContainer),
        ),
        // Centered avatar stacked below banner
        const SizedBox(height: 16),
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.surface, width: 3),
                ),
                child: Avatar(
                  radius: 44,
                  imageUrl: hasAvatar ? user.avatarUrl : '',
                  fallbackIcon: Icons.person,
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // Online presence dot.
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: user.online ? Colors.green : theme.colorScheme.surface,
                    border: Border.all(color: theme.colorScheme.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Nickname (falls back to username in displayName)
        Center(
          child: VerifiedName(
            name: user.displayName,
            verified: user.isVerified,
            bot: user.isBot,
            memberLevel: user.memberLevel,
            memberActive: user.hasActiveMembership,
            nameColor: user.nameColor,
            nameColorTo: user.nameColorTo,
            nameColors: user.nameColors,
            nameGradientDirection: user.nameGradientDirection,
            nameDynamic: user.nameDynamic,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            user.online
                ? 'online'.tr()
                : (user.lastSeenAt != null
                    ? 'lastSeen'.tr().replaceFirst(
                        '{time}', _formatLastSeen(user.lastSeenAt!))
                    : 'offline'.tr()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: user.online
                  ? Colors.green
                  : theme.colorScheme.onSurfaceVariant,
            ),
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
        if (user.level > 0) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ExperienceBar(user: user),
          ),
        ],
        const SizedBox(height: 12),
        // Follow counts row
        _buildFollowCountsRow(theme, user),
        const SizedBox(height: 8),
        _buildFollowButton(theme, user),
        if (user.role == 'admin') ...[
          const SizedBox(height: 8),
          Center(
            child: Chip(
              avatar: const Icon(Icons.admin_panel_settings, size: 16),
              label: Text('admin'.tr()),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFollowCountsRow(ThemeData theme, User user) {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null) return const SizedBox.shrink();

    // A target that hides its follow lists shows a lock note instead of the
    // tappable counts; only the account owner still sees their own numbers.
    if (user.hideFollowLists && auth.user?.id != user.id) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'followListsHidden'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

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
                  text: ' ${'followers'.tr()}',
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
                  text: ' ${'following'.tr()}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        InkWell(
          onTap: () => _openFollowList(FollowListType.friends),
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '${user.friendCount}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' ${'friends'.tr()}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFollowButton(ThemeData theme, User user) {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null) return const SizedBox.shrink();
    final isSelf = auth.user?.id == user.id;
    if (isSelf) return const SizedBox.shrink();

    if (user.isFriend) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              avatar: Icon(Icons.group, size: 16, color: theme.colorScheme.primary),
              label: Text('friends'.tr()),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _followLoading ? null : () => _toggleFollow(false),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(140, 36),
                side: BorderSide(color: theme.colorScheme.outline),
              ),
              child: _followLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('unfollow'.tr()),
            ),
          ],
        ),
      );
    }

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
              : Text('unfollow'.tr()),
        ),
      );
    }

    return Center(
      child: FilledButton(
        onPressed: _followLoading ? null : () => _toggleFollow(true),
        style: FilledButton.styleFrom(minimumSize: const Size(140, 36)),
        child: _followLoading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text('follow'.tr()),
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
        isFriend: false,
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
