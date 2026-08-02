import 'package:flutter/material.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/services/api_service.dart';

/// Reaction metadata: emoji + material icons for each supported reaction.
const Map<String, ({String emoji, IconData icon, IconData activeIcon})> kReactions = {
  'like': (emoji: '👍', icon: Icons.thumb_up_outlined, activeIcon: Icons.thumb_up),
  'dislike': (emoji: '👎', icon: Icons.thumb_down_outlined, activeIcon: Icons.thumb_down),
  'love': (emoji: '❤️', icon: Icons.favorite_outline, activeIcon: Icons.favorite),
  'haha': (emoji: '😂', icon: Icons.sentiment_very_satisfied_outlined, activeIcon: Icons.sentiment_very_satisfied),
  'wow': (emoji: '😮', icon: Icons.mood_outlined, activeIcon: Icons.mood),
  'sad': (emoji: '😢', icon: Icons.sentiment_dissatisfied_outlined, activeIcon: Icons.sentiment_dissatisfied),
  'angry': (emoji: '😠', icon: Icons.sentiment_very_dissatisfied_outlined, activeIcon: Icons.sentiment_very_dissatisfied),
};

/// Additional reactions revealed by the "more" picker (beyond like/dislike).
const List<String> kMoreReactions = ['love', 'haha', 'wow', 'sad', 'angry'];

/// A compact post action row: like / dislike / more reactions plus a view
/// count. Reacting optimistically updates counts and syncs with the server.
class PostReactionBar extends StatefulWidget {
  final Post post;
  final String? token;
  final ValueChanged<Post> onChanged;
  final VoidCallback? onUnauthenticated;

  const PostReactionBar({
    super.key,
    required this.post,
    required this.token,
    required this.onChanged,
    this.onUnauthenticated,
  });

  @override
  State<PostReactionBar> createState() => _PostReactionBarState();
}

class _PostReactionBarState extends State<PostReactionBar> {
  final ApiService _api = ApiService();
  late Map<String, int> _reactions;
  late String _myReaction;
  bool _busy = false;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    _reactions = Map.of(post.reactions);
    _myReaction = post.myReaction;
  }

  @override
  void didUpdateWidget(covariant PostReactionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.reactions != post.reactions || oldWidget.post.myReaction != post.myReaction) {
      _reactions = Map.of(post.reactions);
      _myReaction = post.myReaction;
    }
  }

  Future<void> _toggle(String reaction) async {
    final token = widget.token;
    if (token == null) {
      widget.onUnauthenticated?.call();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);

    final removing = _myReaction == reaction;
    // Optimistic update.
    final prevReactions = Map.of(_reactions);
    final prevMine = _myReaction;
    setState(() {
      if (removing) {
        _decrement(reaction);
        _myReaction = '';
      } else {
        if (_myReaction.isNotEmpty) {
          _decrement(_myReaction);
        }
        _increment(reaction);
        _myReaction = reaction;
      }
    });

    try {
      final updated = removing
          ? await _api.removePostReaction(post.id, token)
          : await _api.reactToPost(post.id, reaction, token);
      if (!mounted) return;
      widget.onChanged(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reactions = prevReactions;
        _myReaction = prevMine;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _increment(String reaction) {
    _reactions[reaction] = (_reactions[reaction] ?? 0) + 1;
  }

  void _decrement(String reaction) {
    final count = _reactions[reaction] ?? 0;
    if (count <= 1) {
      _reactions.remove(reaction);
    } else {
      _reactions[reaction] = count - 1;
    }
  }

  Future<void> _showMore(BuildContext context) async {
    final token = widget.token;
    if (token == null) {
      widget.onUnauthenticated?.call();
      return;
    }
    final reaction = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'More reactions',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final key in kMoreReactions)
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(key),
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Text(kReactions[key]!.emoji, style: const TextStyle(fontSize: 28)),
                            const SizedBox(height: 2),
                            Text(
                              key,
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (reaction != null) {
      await _toggle(reaction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final views = post.viewCount > 0 ? post.viewCount : null;
    final unique = post.uniqueViews > 0 ? post.uniqueViews : null;

    return Row(
      children: [
        _ReactionButton(
          key_: 'like',
          count: _reactions['like'],
          active: _myReaction == 'like',
          onTap: () => _toggle('like'),
        ),
        _ReactionButton(
          key_: 'dislike',
          count: _reactions['dislike'],
          active: _myReaction == 'dislike',
          onTap: () => _toggle('dislike'),
        ),
        InkWell(
          onTap: () => _showMore(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.add_reaction_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                if (post.reactionCount > 2)
                  const SizedBox(width: 4),
                if (post.reactionCount > 2)
                  Text(
                    '${post.reactionCount}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (views != null)
          _StatChip(icon: Icons.visibility_outlined, label: '$views'),
        if (unique != null && unique != views)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _StatChip(icon: Icons.person_outline, label: '$unique'),
          ),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String key_;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.key_,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = kReactions[key_]!;
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(active ? meta.activeIcon : meta.icon, size: 18, color: color),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
