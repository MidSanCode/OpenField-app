import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/media_image.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/draft_service.dart';
import 'package:openfield/data/services/realtime_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/pages/posts/post_detail_page.dart';
import 'package:openfield/widgets/post_card.dart';
import 'package:openfield/widgets/markdown_content.dart';

/// A media item in the composer: either an existing server attachment
/// (has [attachmentId] + [url]) or a newly picked local image (has [localPath]).
class ComposerMedia {
  final int? attachmentId;
  final String? url;
  final String? localPath;

  const ComposerMedia.attachment(int this.attachmentId, String this.url) : localPath = null;

  const ComposerMedia.local(String this.localPath)
      : attachmentId = null,
        url = null;

  String get displayUrl => url ?? localPath ?? '';
}

class PostsPage extends StatefulWidget {
  const PostsPage({super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<Post> _posts = [];
  bool _isLoading = true;
  bool _isPosting = false;
  String? _error;
  String _query = '';
  StreamSubscription<PushEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _realtimeSub = RealtimeService.instance.events.listen(_onRealtimeEvent);
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      _loadPosts();
    });
  }

  /// Prepends freshly created posts (broadcast by the push service) to the feed.
  void _onRealtimeEvent(PushEvent event) {
    if (event.type != 'post.created' || !mounted) return;
    if (_query.isNotEmpty) return;
    final post = Post.fromJson(event.data);
    final exists = _posts.any((p) => p.id == post.id);
    if (exists) return;
    setState(() => _posts = [post, ..._posts]);
  }

  Future<void> _loadPosts() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final posts = await _apiService.getPosts(token: authService.accessToken, query: _query);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openAuthorProfile(int userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
    );
  }

  void _openComposer() {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('loginWithOIDC'.tr())),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ComposerDialog(
        onSubmit: (content, media) => _submitPost(content, media),
        isPosting: _isPosting,
      ),
    );
  }

  void _openEdit(Post post) {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.isAuthenticated) return;
    final media = post.attachments
        .where((a) => a.isImage)
        .map((a) => ComposerMedia.attachment(a.id, a.url))
        .toList();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ComposerDialog(
        onSubmit: (content, items) => _submitPost(content, items, postId: post.id),
        isPosting: _isPosting,
        initialContent: post.content,
        initialMedia: media,
        isEditing: true,
      ),
    );
  }

  Future<bool> _submitPost(String content, List<ComposerMedia> media, {int? postId}) async {
    if (content.trim().isEmpty && media.isEmpty) return false;

    final authService = Provider.of<AuthService>(context, listen: false);
    setState(() => _isPosting = true);
    try {
      final token = authService.accessToken!;
      final attachmentIds = <int>[];
      for (final item in media) {
        if (item.attachmentId != null) {
          attachmentIds.add(item.attachmentId!);
        } else if (item.localPath != null) {
          final att = await _apiService.uploadAttachmentSmart(item.localPath!, token);
          attachmentIds.add(att.id);
        }
      }
      if (postId == null) {
        await _apiService.createPost(content, token, attachmentIds: attachmentIds);
      } else {
        await _apiService.updatePost(postId, content, token, attachmentIds: attachmentIds);
      }
      await _loadPosts();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isPosting = false);
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
      await _loadPosts();
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
    final currentUserId = Provider.of<AuthService>(context).user?.id;

    return Scaffold(
      appBar: AppBar(title: Text('appTitle'.tr())),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        tooltip: 'createPost'.tr(),
        child: const Icon(Icons.edit),
      ),
      body: _buildBody(currentUserId),
    );
  }

  Widget _buildBody(int? currentUserId) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'searchPosts'.tr(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        Expanded(child: _buildFeed(currentUserId)),
      ],
    );
  }

  Widget _buildFeed(int? currentUserId) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('loadFailed'.tr()),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadPosts, child: Text('retry'.tr())),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Text(_query.isNotEmpty ? 'noSearchResults'.tr() : 'noPosts'.tr()),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          final authService = Provider.of<AuthService>(context, listen: false);
          return PostCard(
            post: post,
            isMine: post.userId == currentUserId,
            onEdit: () => _openEdit(post),
            onDelete: () => _deletePost(post),
            onTapAuthor: () => _openAuthorProfile(post.userId),
            onTapReply: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
              );
            },
            token: authService.accessToken,
            onPostChanged: (updated) {
              setState(() {
                _posts = _posts.map((p) => p.id == updated.id ? updated : p).toList();
              });
            },
            onUnauthenticated: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('loginWithOIDC'.tr())),
              );
            },
          );
        },
      ),
    );
  }
}

class _ComposerDialog extends StatefulWidget {
  final Future<bool> Function(String content, List<ComposerMedia> media) onSubmit;
  final bool isPosting;
  final String initialContent;
  final List<ComposerMedia> initialMedia;
  final bool isEditing;

  const _ComposerDialog({
    required this.onSubmit,
    required this.isPosting,
    this.initialContent = '',
    this.initialMedia = const [],
    this.isEditing = false,
  });

  @override
  State<_ComposerDialog> createState() => _ComposerDialogState();
}

class _ComposerDialogState extends State<_ComposerDialog> {
  final DraftService _draftService = DraftService();
  late final TextEditingController _controller;
  late List<ComposerMedia> _media;
  String? _currentDraftId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _media = List.of(widget.initialMedia);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (!mounted || files.isEmpty) return;
    setState(() {
      _media.addAll(files.map((f) => ComposerMedia.local(f.path)));
      if (_media.length > 9) {
        _media.removeRange(9, _media.length);
      }
    });
  }

  /// Saves the current composer content as a draft. Saving a fresh post creates
  /// a new draft; saving one that was loaded from the draft box updates it.
  Future<void> _saveDraft({bool notify = true}) async {
    final localPaths = _media
        .where((m) => m.localPath != null)
        .map((m) => m.localPath!)
        .toList();
    final id = _currentDraftId ?? DateTime.now().microsecondsSinceEpoch.toString();
    await _draftService.save(PostDraft(
      id: id,
      content: _controller.text,
      images: localPaths,
      updatedAt: DateTime.now(),
    ));
    if (mounted) setState(() => _currentDraftId = id);
    if (notify && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('draftSaved'.tr())),
      );
    }
  }

  /// Opens the draft box listing every saved draft, allowing one to be loaded
  /// into the composer or deleted.
  Future<void> _openDrafts() async {
    final drafts = await _draftService.list();
    if (!mounted) return;
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('noDraft'.tr())),
      );
      return;
    }
    final picked = await showDialog<PostDraft>(
      context: context,
      builder: (context) => _DraftBoxDialog(drafts: drafts),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _controller.text = picked.content;
      _currentDraftId = picked.id;
      final existing = _media
          .where((m) => m.attachmentId != null)
          .map((m) => m)
          .toList();
      _media = [...existing, ...picked.images.map((p) => ComposerMedia.local(p))];
    });
  }

  /// Closes the dialog, auto-saving a draft when there is unsent content.
  Future<void> _close() async {
    if (_controller.text.trim().isNotEmpty || _media.isNotEmpty) {
      await _saveDraft(notify: false);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    final success = await widget.onSubmit(_controller.text.trim(), _media);
    if (mounted && success) {
      final draftId = _currentDraftId;
      if (draftId != null) {
        await _draftService.delete(draftId);
      }
      if (mounted) Navigator.of(context).pop();
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  void _showPreview() {
    showDialog(
      context: context,
      builder: (_) => _ComposerPreviewDialog(
        content: _controller.text,
        media: _media,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = _isSubmitting || widget.isPosting;

    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.isEditing ? 'editPost'.tr() : 'createPost'.tr(),
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: isBusy ? null : _close,
                    child: Text('cancel'.tr()),
                  ),
                  IconButton(
                    onPressed: isBusy ? null : _showPreview,
                    icon: const Icon(Icons.visibility_outlined),
                    tooltip: 'preview'.tr(),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: isBusy ? null : _submit,
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(widget.isEditing ? 'save'.tr() : 'post'.tr()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          minLines: 8,
                          expands: false,
                          autofocus: !widget.isEditing,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: 'postContent'.tr(),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_media.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < _media.length; i++)
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: _buildThumb(_media[i], theme),
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() => _media.removeAt(i));
                                        },
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close,
                                              size: 16, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: isBusy ? null : _pickImages,
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'addImages'.tr(),
                  ),
                  IconButton(
                    onPressed: isBusy ? null : _saveDraft,
                    icon: const Icon(Icons.save_outlined),
                    tooltip: 'save'.tr(),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: isBusy ? null : _openDrafts,
                    icon: const Icon(Icons.drafts_outlined),
                    tooltip: 'drafts'.tr(),
                  ),
                  if (isBusy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumb(ComposerMedia media, ThemeData theme) {
    final child = SizedBox(
      width: 90,
      height: 90,
      child: Image.file(
        File(media.localPath ?? ''),
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
    if (media.attachmentId == null) return child;

    return SizedBox(
      width: 90,
      height: 90,
      child: MediaImage(
        url: media.url ?? '',
        fit: BoxFit.cover,
      ),
    );
  }
}

class _ComposerPreviewDialog extends StatelessWidget {
  final String content;
  final List<ComposerMedia> media;

  const _ComposerPreviewDialog({required this.content, required this.media});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('preview'.tr(), style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'cancel'.tr(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (media.isEmpty && content.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'postContent'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (content.trim().isNotEmpty)
                MarkdownContent(
                  data: content,
                  padding: EdgeInsets.zero,
                ),
              if (content.trim().isNotEmpty && media.isNotEmpty)
                const SizedBox(height: 12),
              if (media.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in media)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildThumb(item, theme),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumb(ComposerMedia media, ThemeData theme) {
    if (media.attachmentId != null) {
      return SizedBox(
        width: 90,
        height: 90,
        child: MediaImage(
          url: media.url ?? '',
          fit: BoxFit.cover,
        ),
      );
    }
    return SizedBox(
      width: 90,
      height: 90,
      child: Image.file(
        File(media.localPath ?? ''),
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

/// Lists every saved draft. Tapping a draft loads it into the composer; the
/// trash button offers to delete a single draft.
class _DraftBoxDialog extends StatefulWidget {
  final List<PostDraft> drafts;

  const _DraftBoxDialog({required this.drafts});

  @override
  State<_DraftBoxDialog> createState() => _DraftBoxDialogState();
}

class _DraftBoxDialogState extends State<_DraftBoxDialog> {
  late final List<PostDraft> _drafts = List.of(widget.drafts);

  Future<void> _confirmDelete(PostDraft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('deleteDraftConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final draftsService = DraftService();
      await draftsService.delete(draft.id);
      if (!mounted) return;
      setState(() => _drafts.removeWhere((d) => d.id == draft.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.drafts_outlined,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('drafts'.tr(), style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'cancel'.tr(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_drafts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('noDraft'.tr())),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _drafts.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final draft = _drafts[index];
                      final preview = draft.content.isEmpty
                          ? '${draft.images.length} image(s)'
                          : draft.content;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          draft.images.isEmpty
                              ? Icons.notes
                              : Icons.image_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_formatDate(draft.updatedAt)),
                        onTap: () => Navigator.of(context).pop(draft),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'delete'.tr(),
                          onPressed: () => _confirmDelete(draft),
                        ),
                      );
                    },
                  ),
                ),
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
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
