import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'package:openfield/widgets/check_card.dart';
import 'package:openfield/widgets/markdown_content.dart';

/// A media item in the composer: either an existing server attachment
/// (has [attachmentId] + [url]) or a newly picked local file (has [localPath]).
/// Any file type is allowed; images render as thumbnails, everything else as
/// a generic file chip.
class ComposerMedia {
  final int? attachmentId;
  final String? url;
  final String? localPath;

  const ComposerMedia.attachment(int this.attachmentId, String this.url) : localPath = null;

  const ComposerMedia.local(String this.localPath)
      : attachmentId = null,
        url = null;

  String get displayUrl => url ?? localPath ?? '';

  static const _imageExtensions = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'avif', 'svg',
  };

  /// True when the item should render as an image thumbnail rather than a
  /// generic file chip.
  bool get isImageLike {
    final path = localPath ?? url ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
  }
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
  bool _searchActive = false;
  String? _error;
  String _query = '';
  /// Active tag filter; null when the feed shows everything.
  String? _tag;

  // Advanced search filters (combined with the keyword server-side).
  String _authorFilter = '';
  DateTime? _fromFilter;
  DateTime? _toFilter;

  bool get _hasFilters =>
      _authorFilter.isNotEmpty || _fromFilter != null || _toFilter != null;

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

  /// Toggles the AppBar search field. Closing it clears the active query and
  /// restores the full feed.
  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchController.clear();
        _searchDebounce?.cancel();
        _query = '';
      }
    });
    _loadPosts();
  }

  /// Sets the active tag filter and reloads the feed restricted to that tag.
  void _setTag(String tag) {
    setState(() => _tag = tag);
    _loadPosts();
  }

  /// Clears the tag filter and restores the full feed.
  void _clearTag() {
    setState(() => _tag = null);
    _loadPosts();
  }

  /// Opens the advanced filter sheet: author name substring + created-at date
  /// range. Applied filters re-run the current search immediately.
  Future<void> _openPostFilters() async {
    final authorController =
        TextEditingController(text: _authorFilter);
    DateTime? from = _fromFilter;
    DateTime? to = _toFilter;
    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('postFilterTitle'.tr(),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: authorController,
                  decoration: InputDecoration(
                    labelText: 'postFilterAuthor'.tr(),
                    hintText: 'postFilterAuthorHint'.tr(),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range_outlined),
                  title: Text('postFilterFrom'.tr()),
                  subtitle: () {
                    final f = from;
                    return f != null
                        ? Text('${f.year}/${f.month}/${f.day}')
                        : null;
                  }(),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: from ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setSheetState(() => from = picked);
                  },
                  trailing: from != null
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setSheetState(() => from = null),
                        )
                      : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range_outlined),
                  title: Text('postFilterTo'.tr()),
                  subtitle: () {
                    final t = to;
                    return t != null
                        ? Text('${t.year}/${t.month}/${t.day}')
                        : null;
                  }(),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: to ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setSheetState(() => to = picked);
                  },
                  trailing: to != null
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setSheetState(() => to = null),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        authorController.clear();
                        setSheetState(() {
                          from = null;
                          to = null;
                        });
                      },
                      child: Text('chatSearchClearFilters'.tr()),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text('apply'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != true || !mounted) return;
    setState(() {
      _authorFilter = authorController.text.trim();
      _fromFilter = from;
      _toFilter = to;
    });
    _loadPosts();
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
      final posts = await _apiService.getPosts(
        token: authService.accessToken,
        query: _query,
        author: _authorFilter,
        from: _fromFilter,
        to: _toFilter,
        tag: _tag,
      );
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

  void _openPostDetail(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailPage(post: post)),
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
        onSubmit: (content, media, visibility, checkId, tags) =>
            _submitPost(content, media, visibility: visibility, checkId: checkId, tags: tags),
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
        onSubmit: (content, items, visibility, _, tags) =>
            _submitPost(content, items, postId: post.id, visibility: visibility, tags: tags),
        isPosting: _isPosting,
        initialContent: post.content,
        initialMedia: media,
        initialVisibility: post.visibility,
        isEditing: true,
      ),
    );
  }

  Future<bool> _submitPost(String content, List<ComposerMedia> media,
      {int? postId,
      String visibility = 'public',
      int checkId = 0,
      List<String> tags = const []}) async {
    if (content.trim().isEmpty && media.isEmpty) return false;

    final authService = Provider.of<AuthService>(context, listen: false);
    setState(() => _isPosting = true);
    final locals = media.where((m) => m.localPath != null).toList();
    final progress = ValueNotifier<double>(0.0);

    // Modal progress dialog while attachments are uploading.
    Future<void>? progressDialog;
    if (locals.isNotEmpty && mounted) {
      progressDialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UploadProgressDialog(notifier: progress, total: locals.length),
      );
    }

    Future<void> closeProgress() async {
      if (progressDialog == null) return;
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await progressDialog;
      progressDialog = null;
    }

    try {
      final token = authService.accessToken!;
      final attachmentIds = <int>[];
      var doneFiles = 0;
      for (final item in media) {
        if (item.attachmentId != null) {
          attachmentIds.add(item.attachmentId!);
        } else if (item.localPath != null) {
          final base = doneFiles / locals.length;
          final att = await _apiService.uploadAttachmentSmart(
            item.localPath!,
            token,
            onProgress: (p) {
              progress.value =
                  (base + p / locals.length).clamp(0.0, 1.0);
            },
          );
          attachmentIds.add(att.id);
          doneFiles++;
        }
      }
      await closeProgress();
      if (postId == null) {
        await _apiService.createPost(content, token,
            attachmentIds: attachmentIds,
            visibility: visibility,
            checkId: checkId,
            tags: tags);
      } else {
        await _apiService.updatePost(postId, content, token,
            attachmentIds: attachmentIds, visibility: visibility);
      }
      await _loadPosts();
      return true;
    } catch (e) {
      await closeProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
      return false;
    } finally {
      progress.dispose();
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
      appBar: AppBar(
        title: _searchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'searchPosts'.tr(),
                  border: InputBorder.none,
                ),
              )
            : Text('appTitle'.tr()),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune,
              color: _hasFilters ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: 'postFilterTitle'.tr(),
            onPressed: _openPostFilters,
          ),
          IconButton(
            icon: Icon(_searchActive ? Icons.close : Icons.search),
            tooltip: 'searchPosts'.tr(),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        tooltip: 'createPost'.tr(),
        child: const Icon(Icons.edit),
      ),
      body: _buildFeed(currentUserId),
    );
  }

  Widget _buildFeed(int? currentUserId) {
    final theme = Theme.of(context);
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
        child: Text(
            _query.isNotEmpty || _hasFilters ? 'noSearchResults'.tr() : 'noPosts'.tr()),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: Column(
        children: [
          if (_tag != null)
            Material(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '#$_tag',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'clear'.tr(),
                      onPressed: _clearTag,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
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
                  onTapReply: () => _openPostDetail(post),
                  onTap: () => _openPostDetail(post),
                  token: authService.accessToken,
                  onTapTag: (tag) => _setTag(tag),
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
          ),
        ],
      ),
    );
  }
}

class _ComposerDialog extends StatefulWidget {
  final Future<bool> Function(String content, List<ComposerMedia> media, String visibility, int checkId, List<String> tags) onSubmit;
  final bool isPosting;
  final String initialContent;
  final List<ComposerMedia> initialMedia;
  final String initialVisibility;
  final bool isEditing;

  const _ComposerDialog({
    required this.onSubmit,
    required this.isPosting,
    this.initialContent = '',
    this.initialMedia = const [],
    this.initialVisibility = 'public',
    this.isEditing = false,
  });

  @override
  State<_ComposerDialog> createState() => _ComposerDialogState();
}

class _ComposerDialogState extends State<_ComposerDialog> {
  final DraftService _draftService = DraftService();
  late final TextEditingController _controller;
  late List<ComposerMedia> _media;
  late String _visibility;
  String? _currentDraftId;
  bool _isSubmitting = false;

  /// Check created via the compose dialog and attached to this post on
  /// submit. A check left unattached (composer cancelled) simply expires and
  /// refunds to the wallet.
  int? _pendingCheckId;

  /// Free-form tags attached to the post. The server normalises (lowercase,
  /// trim, dedupe, cap at 20) so the client only does light sanitising.
  final List<String> _pendingTags = [];
  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _media = List.of(widget.initialMedia);
    _visibility = widget.initialVisibility;
  }

  @override
  void dispose() {
    _controller.dispose();
    _tagController.dispose();
    super.dispose();
  }

  /// Attachment source picker: gallery images, gallery videos, or arbitrary
  /// files from the system file manager. Videos and files also accept
  /// multiple selections.
  Future<void> _attachFromSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('attachFromGallery'.tr()),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: Text('attachFromVideos'.tr()),
              onTap: () => Navigator.of(sheetContext).pop('video'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text('attachFromFiles'.tr()),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    List<ComposerMedia> picked = [];
    if (choice == 'image') {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      picked = files.map((f) => ComposerMedia.local(f.path)).toList();
    } else if (choice == 'video') {
      final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true);
      picked = (result?.files ?? const [])
          .where((f) => f.path != null)
          .map((f) => ComposerMedia.local(f.path!))
          .toList();
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
      picked = (result?.files ?? const [])
          .where((f) => f.path != null)
          .map((f) => ComposerMedia.local(f.path!))
          .toList();
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _media.addAll(picked);
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

  /// Adds a tag (from the tag field) after light normalisation. Entering an
  /// already-added tag is a no-op.
  void _addTag() {
    final raw = _tagController.text.trim().replaceAll('#', '');
    if (raw.isEmpty) return;
    setState(() {
      if (!_pendingTags.contains(raw)) _pendingTags.add(raw);
      _tagController.clear();
    });
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    final success = await widget.onSubmit(
        _controller.text.trim(), _media, _visibility, _pendingCheckId ?? 0, _pendingTags);
    if (mounted && success) {
      final draftId = _currentDraftId;
      if (draftId != null) {
        await _draftService.delete(draftId);
      }
      if (mounted) Navigator.of(context).pop();
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  Future<void> _attachCheck() async {
    final id = await showCheckComposeDialog(context);
    if (!mounted || id == null) return;
    setState(() => _pendingCheckId = id);
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
              if (_pendingCheckId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.redeem,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text('checkAttached'.tr())),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'removeAttachment'.tr(),
                        onPressed: () =>
                            setState(() => _pendingCheckId = null),
                      ),
                    ],
                  ),
                ),
              if (_pendingTags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in _pendingTags)
                        Chip(
                          label: Text('#$tag'),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () =>
                              setState(() => _pendingTags.remove(tag)),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.tag, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _tagController,
                        onSubmitted: (_) => _addTag(),
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'addTag'.tr(),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: 'addTag'.tr(),
                      onPressed: _addTag,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: isBusy ? null : _attachFromSheet,
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'addAttachment'.tr(),
                  ),
                  IconButton(
                    onPressed: isBusy ? null : _attachCheck,
                    icon: Icon(
                      Icons.redeem,
                      color: _pendingCheckId != null
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    tooltip: 'checkAttach'.tr(),
                  ),
                  IconButton(
                    onPressed: isBusy ? null : _saveDraft,
                    icon: const Icon(Icons.save_outlined),
                    tooltip: 'save'.tr(),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'visibility'.tr(),
                    icon: Icon(_visibilityIcon(_visibility)),
                    initialValue: _visibility,
                    onSelected: (value) => setState(() => _visibility = value),
                    itemBuilder: (context) => [
                      for (final v in const ['public', 'login', 'friends', 'private'])
                        PopupMenuItem(
                          value: v,
                          child: _VisibilityItem(value: v),
                        ),
                    ],
                  ),
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

  IconData _visibilityIcon(String value) {
    switch (value) {
      case 'public':
        return Icons.public;
      case 'login':
        return Icons.login;
      case 'friends':
        return Icons.group;
      case 'private':
        return Icons.lock_outline;
      default:
        return Icons.public;
    }
  }

  Widget _buildThumb(ComposerMedia media, ThemeData theme) {
    if (!media.isImageLike) {
      // Generic file chip: icon + filename instead of an image preview.
      final name = (media.localPath ?? media.url ?? '')
          .split(Platform.pathSeparator)
          .last;
      return Container(
        width: 90,
        height: 90,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 26, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
            ),
          ],
        ),
      );
    }
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
    if (!media.isImageLike) {
      // Generic file chip mirrors the composer's rendering for non-images.
      final name = (media.localPath ?? '')
          .split(Platform.pathSeparator)
          .last;
      return Container(
        width: 90,
        height: 90,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 26, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
            ),
          ],
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

/// A post visibility choice shown inside the composer's visibility menu.
class _VisibilityItem extends StatelessWidget {
  final String value;

  const _VisibilityItem({required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, hint) = switch (value) {
      'public' => (Icons.public, 'visibilityPublic', 'visibilityPublicHint'),
      'login' => (Icons.login, 'visibilityLogin', 'visibilityLoginHint'),
      'friends' => (Icons.group, 'visibilityFriends', 'visibilityFriendsHint'),
      'private' => (Icons.lock_outline, 'visibilityPrivate', 'visibilityPrivateHint'),
      _ => (Icons.public, 'visibilityPublic', 'visibilityPublicHint'),
    };
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.tr(), style: theme.textTheme.bodyLarge),
            Text(
              hint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Modal dialog shown while post attachments are uploading: one aggregate
/// progress bar plus the current fraction. The owner pops it when uploads
/// finish (or fail).
class _UploadProgressDialog extends StatelessWidget {
  final ValueListenable<double> notifier;
  final int total;

  const _UploadProgressDialog({required this.notifier, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      content: ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (context, value, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('uploadingAttachment'.tr(),
                        style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text('${(value * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          );
        },
      ),
    );
  }
}
