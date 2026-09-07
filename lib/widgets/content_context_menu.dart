import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openfield/data/services/api_service.dart';

/// Base URL for shareable content links, derived from the active API server.
/// Posts resolve to `{base}/posts/{id}` and replies to
/// `{base}/posts/{postId}#reply-{replyId}`.
String get postLinkBase => '${ApiService.serverHost}/posts';

/// Builds the shareable URL for a post: `{postLinkBase}/{postId}`.
String postLink(int postId) => '$postLinkBase/$postId';

/// Builds the deep-link URL for a reply anchor on the post page.
String replyLink(int postId, int replyId) => '$postLinkBase/$postId#reply-$replyId';

/// Action identifiers used by the post/reply context menus (shown both on
/// desktop right-click and mobile long-press).
class ContentAction {
  /// Copies the shareable post/reply link to the clipboard.
  static const String copyLink = 'copyLink';
  /// Adds the content to the viewer's favorites.
  static const String favorite = 'favorite';
  /// Removes the content from the viewer's favorites.
  static const String unfavorite = 'unfavorite';
  /// Opens the editor for the author's own content.
  static const String edit = 'edit';
  /// Deletes the author's own content (shown as destructive).
  static const String delete = 'delete';
  /// Starts a reply to the content.
  static const String reply = 'reply';
  /// Opens the visibility (who can see this) picker.
  static const String visibility = 'visibility';
  /// Opens the composer prefilled with a quote of the content.
  static const String quote = 'quote';
  /// Reposts the content as-is.
  static const String repost = 'repost';
  /// Pins the author's own post.
  static const String pin = 'pin';
  /// Unpins the author's own post.
  static const String unpin = 'unpin';
}

/// Builds the shared menu items for a post or a reply. Only an authenticated,
/// authoring user gets [ContentAction.edit]/[ContentAction.delete]; favorite /
/// unfavorite toggle on the current state. [showQuote]/[showRepost] reveal the
/// quote/repost entries; callers hide them when the matching callback is
/// unavailable (e.g. unauthenticated context). [pinned] reveals the
/// pin/unpin toggle for the author's own posts.
List<PopupMenuEntry<String>> buildContentMenuItems({
  required bool isMine,
  required bool isFavorite,
  bool includeReply = false,
  bool showQuote = false,
  bool showRepost = false,
  bool pinned = false,
}) {
  final items = <PopupMenuEntry<String>>[
    PopupMenuItem(
      value: ContentAction.copyLink,
      child: _MenuLabel(
        icon: Icons.link,
        text: 'copyPostLink'.tr(),
      ),
    ),
    if (includeReply)
      PopupMenuItem(
        value: ContentAction.reply,
        child: _MenuLabel(
          icon: Icons.reply,
          text: 'reply'.tr(),
        ),
      ),
    if (showQuote)
      PopupMenuItem(
        value: ContentAction.quote,
        child: _MenuLabel(
          icon: Icons.format_quote_outlined,
          text: 'postQuote'.tr(),
        ),
      ),
    if (showRepost)
      PopupMenuItem(
        value: ContentAction.repost,
        child: _MenuLabel(
          icon: Icons.repeat_outlined,
          text: 'postRepost'.tr(),
        ),
      ),
    if (isMine)
      PopupMenuItem(
        value: pinned ? ContentAction.unpin : ContentAction.pin,
        child: _MenuLabel(
          icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
          text: pinned ? 'unpinPost'.tr() : 'pinPost'.tr(),
        ),
      ),
    PopupMenuItem(
      value: isFavorite ? ContentAction.unfavorite : ContentAction.favorite,
      child: _MenuLabel(
        icon: isFavorite ? Icons.bookmark : Icons.bookmark_border,
        text: isFavorite ? 'removeFavorite'.tr() : 'addFavorite'.tr(),
      ),
    ),
    if (isMine)
      PopupMenuItem(
        value: ContentAction.edit,
        child: _MenuLabel(
          icon: Icons.edit_outlined,
          text: 'edit'.tr(),
        ),
      ),
    if (isMine)
      PopupMenuItem(
        value: ContentAction.delete,
        child: _MenuLabel(
          icon: Icons.delete_outline,
          text: 'delete'.tr(),
          destructive: true,
        ),
      ),
  ];
  return items;
}

/// Shows a positioned popup menu at [globalPosition] (used for desktop
/// right-click via `Listener`/`onSecondaryTapDown`). Returns the chosen action
/// or null when dismissed.
Future<String?> showContentMenuAt(
  BuildContext context,
  Offset globalPosition, {
  required List<PopupMenuEntry<String>> items,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final position = RelativeRect.fromLTRB(
    globalPosition.dx,
    globalPosition.dy,
    (overlay?.size.width ?? 0) - globalPosition.dx,
    (overlay?.size.height ?? 0) - globalPosition.dy,
  );
  return showMenu<String>(context: context, position: position, items: items);
}

/// Shows the content menu as a modal bottom sheet (mobile long-press). Returns
/// the chosen action or null when dismissed.
Future<String?> showContentBottomSheet(
  BuildContext context, {
  required List<PopupMenuEntry<String>> items,
}) {
  final entries = items
      .map((e) => e is PopupMenuItem<String> ? e.value : null)
      .whereType<String>()
      .toList();
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in entries)
            ListTile(
              leading: Icon(_iconFor(value)),
              title: Text(
                _labelFor(value),
                style: value == ContentAction.delete
                    ? TextStyle(color: Theme.of(ctx).colorScheme.error)
                    : null,
              ),
              onTap: () => Navigator.of(ctx).pop(value),
            ),
        ],
      ),
    ),
  );
}

IconData _iconFor(String value) {
  switch (value) {
    case ContentAction.copyLink:
      return Icons.link;
    case ContentAction.reply:
      return Icons.reply;
    case ContentAction.quote:
      return Icons.format_quote_outlined;
    case ContentAction.repost:
      return Icons.repeat_outlined;
    case ContentAction.pin:
      return Icons.push_pin_outlined;
    case ContentAction.unpin:
      return Icons.push_pin;
    case ContentAction.favorite:
      return Icons.bookmark_border;
    case ContentAction.unfavorite:
      return Icons.bookmark;
    case ContentAction.edit:
      return Icons.edit_outlined;
    case ContentAction.delete:
      return Icons.delete_outline;
    case ContentAction.visibility:
      return Icons.visibility_outlined;
    default:
      return Icons.more_horiz;
  }
}

String _labelFor(String value) {
  switch (value) {
    case ContentAction.copyLink:
      return 'copyPostLink'.tr();
    case ContentAction.reply:
      return 'reply'.tr();
    case ContentAction.quote:
      return 'postQuote'.tr();
    case ContentAction.repost:
      return 'postRepost'.tr();
    case ContentAction.pin:
      return 'pinPost'.tr();
    case ContentAction.unpin:
      return 'unpinPost'.tr();
    case ContentAction.favorite:
      return 'addFavorite'.tr();
    case ContentAction.unfavorite:
      return 'removeFavorite'.tr();
    case ContentAction.edit:
      return 'edit'.tr();
    case ContentAction.delete:
      return 'delete'.tr();
    case ContentAction.visibility:
      return 'visibility'.tr();
    default:
      return value;
  }
}

/// Small row used inside popup menu items so desktop right-click menus look
/// consistent with the app theme.
class _MenuLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool destructive;

  const _MenuLabel({
    required this.icon,
    required this.text,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }
}