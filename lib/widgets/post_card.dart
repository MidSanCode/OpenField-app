import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/core/widgets/pin_dialog.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/widgets/attachment_view.dart';
import 'package:openfield/widgets/check_card.dart';
import 'package:openfield/widgets/content_context_menu.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/post_reaction_bar.dart';
import 'package:openfield/widgets/verified_badge.dart';
import 'package:openfield/core/widgets/avatar.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTapReply;
  final VoidCallback? onTapAuthor;
  final bool showReplies;
  final ValueChanged<Post>? onPostChanged;
  final String? token;
  final VoidCallback? onUnauthenticated;
  /// When true, the content is always rendered in full (used by the post
  /// detail page) and the "view more" affordance is hidden.
  final bool showFullContent;
  /// Card-wide onTap: any blank area of the card (content, attachments and
  /// padding) not already claimed by an inner control opens the post detail
  /// page. Inner controls (author, reply, reactions, tip and the menu) keep
  /// their own handlers.
  final VoidCallback? onTap;
  /// Tapping a tag chip filters the feed by that tag. Null disables the
  /// affordance (e.g. inside the post detail page).
  final ValueChanged<String>? onTapTag;

  const PostCard({
    super.key,
    required this.post,
    this.isMine = false,
    this.onEdit,
    this.onDelete,
    this.onTapReply,
    this.onTapAuthor,
    this.showReplies = true,
    this.onPostChanged,
    this.token,
    this.onUnauthenticated,
    this.showFullContent = false,
    this.onTap,
    this.onTapTag,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  static const int _truncateLength = 200;
  late bool _expanded;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    _expanded = widget.showFullContent || post.content.length <= _truncateLength;
  }

  bool get _isTruncated => post.content.length > _truncateLength;

  String get _displayContent =>
      _expanded || !_isTruncated ? post.content : post.content.substring(0, _truncateLength);

  /// Opens the post context menu, either as a desktop right-click popup at
  /// [position] or as the mobile long-press bottom sheet.
  Future<void> _showContextMenu([Offset? position]) async {
    final items = buildContentMenuItems(
      isMine: widget.isMine,
      isFavorite: post.isFavorite,
    );
    final action = position != null
        ? await showContentMenuAt(context, position, items: items)
        : await showContentBottomSheet(context, items: items);
    if (action == null || !mounted) return;
    await _handleAction(action);
  }

  Future<void> _handleAction(String action) async {
    switch (action) {
      case ContentAction.copyLink:
        await Clipboard.setData(
          ClipboardData(text: postLink(post.id)),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('linkCopied'.tr())),
          );
        }
      case ContentAction.edit:
        widget.onEdit?.call();
      case ContentAction.delete:
        widget.onDelete?.call();
      case ContentAction.favorite:
      case ContentAction.unfavorite:
        await _toggleFavorite();
    }
  }

  Future<void> _toggleFavorite() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      widget.onUnauthenticated?.call();
      return;
    }
    try {
      final api = ApiService();
      final updated = post.isFavorite
          ? await api.unfavoritePost(post.id, token)
          : await api.favoritePost(post.id, token);
      if (!mounted) return;
      widget.onPostChanged?.call(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  /// Preset tip amounts (in coins) offered by the tip dialog.
  static const List<int> _tipPresets = [5, 10, 20, 50, 100];

  Future<void> _tipPost() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      widget.onUnauthenticated?.call();
      return;
    }
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('tipPostTitle'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'tipPostHint'.tr(),
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in _tipPresets)
                  ActionChip(
                    avatar: const Icon(Icons.monetization_on_outlined,
                        size: 16),
                    label: Text('$n'),
                    onPressed: () => Navigator.of(dialogContext).pop(n),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr()),
          ),
        ],
      ),
    );
    if (amount == null || !mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final api = ApiService();
    // The payment PIN authorizes the charge (first-time payers must set one).
    var pin = '';
    if (!(authService.user?.hasPin ?? false)) {
      pin = await showPinDialog(context, isSetting: true) ?? '';
      if (pin.isEmpty || !mounted) return;
      await api.setPin(token, pin);
      await authService.fetchCurrentUser();
    } else {
      pin = await showPinDialog(context, isSetting: false) ?? '';
      if (pin.isEmpty || !mounted) return;
    }
    try {
      await api.tipPost(post.id, amount, token, pin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('tipSuccess'.tr())),
      );
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    }
  }

  /// Formats a cents amount as a compact coin figure (e.g. "12" or "12.5").
  static String _formatCoins(int cents) {
    if (cents % 100 == 0) return '${cents ~/ 100}';
    return (cents / 100).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () => _showContextMenu(),
      onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: widget.onTapAuthor,
                    borderRadius: BorderRadius.circular(24),
                    child: Avatar(
                      radius: 20,
                      imageUrl: post.avatarUrl ?? '',
                      initials: post.authorName.isNotEmpty
                          ? post.authorName.substring(0, 1).toUpperCase()
                          : '',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: widget.onTapAuthor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VerifiedName(
                            name: post.authorName,
                            verified: post.authorVerified,
                            bot: post.isBot,
                            memberLevel: post.memberLevel,
                            memberActive: post.memberActive,
                            nameColor: post.nameColor,
                            nameColorTo: post.nameColorTo,
                            nameColors: post.nameColors,
                            nameGradientDirection: post.nameGradientDirection,
                            nameDynamic: post.nameDynamic,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            _formatDate(post.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') widget.onEdit?.call();
                      if (value == 'delete') widget.onDelete?.call();
                      if (value == 'favorite') _toggleFavorite();
                      if (value == 'copyLink') {
                        Clipboard.setData(
                          ClipboardData(text: postLink(post.id)),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('linkCopied'.tr())),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'copyLink',
                        child: Text('copyPostLink'.tr()),
                      ),
                      PopupMenuItem(
                        value: 'favorite',
                        child: Text(
                          post.isFavorite ? 'removeFavorite'.tr() : 'addFavorite'.tr(),
                        ),
                      ),
                      if (widget.isMine)
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('edit'.tr()),
                        ),
                      if (widget.isMine)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'delete'.tr(),
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MarkdownContent(data: _displayContent),
              if (_isTruncated && !_expanded) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: widget.onTap ?? () => setState(() => _expanded = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      widget.onTap != null ? 'viewDetail'.tr() : 'showMore'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in post.tags)
                      InkWell(
                        onTap: widget.onTapTag == null
                            ? null
                            : () => widget.onTapTag!(tag),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tag,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tag,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (post.attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                AttachmentView(attachments: post.attachments),
              ],
              if (post.check != null) ...[
                const SizedBox(height: 12),
                CheckCard(checkId: post.check!.id, token: widget.token),
              ],
              if (widget.showReplies) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: widget.onTapReply,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              post.replyCount > 0 ? '${post.replyCount}' : 'reply'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: PostReactionBar(
                        post: post,
                        token: widget.token,
                        onChanged: widget.onPostChanged ?? (_) {},
                        onUnauthenticated: widget.onUnauthenticated,
                      ),
                    ),
                    if (!widget.isMine)
                      InkWell(
                        onTap: _tipPost,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.volunteer_activism_outlined,
                                size: 18,
                                color: Colors.orange,
                              ),
                              if (post.tipTotal > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  _formatCoins(post.tipTotal),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
