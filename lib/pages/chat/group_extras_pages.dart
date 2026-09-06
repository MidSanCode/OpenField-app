import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/camp.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/media/media_preview_page.dart';

/// Group announcements: members read, managers publish/delete.
class GroupAnnouncementsPage extends StatefulWidget {
  final int conversationId;
  final bool canManage;

  const GroupAnnouncementsPage({
    super.key,
    required this.conversationId,
    required this.canManage,
  });

  @override
  State<GroupAnnouncementsPage> createState() => _GroupAnnouncementsPageState();
}

class _GroupAnnouncementsPageState extends State<GroupAnnouncementsPage> {
  final ApiService _api = ApiService();
  List<GroupAnnouncement> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final token = Provider.of<AuthService>(context, listen: false).accessToken!;
      final items = await _api.listAnnouncements(widget.conversationId, token);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final content = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final token = Provider.of<AuthService>(context, listen: false).accessToken!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('groupAnnouncementNew'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, maxLength: 200, decoration: InputDecoration(labelText: 'groupAnnouncementTitle'.tr())),
            TextField(controller: content, maxLines: 4, maxLength: 5000, decoration: InputDecoration(labelText: 'groupAnnouncementBody'.tr())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('send'.tr())),
        ],
      ),
    );
    if (ok != true) return;
    if (content.text.trim().isEmpty) return;
    try {
      await _api.createAnnouncement(widget.conversationId, title.text.trim(), content.text.trim(), token);
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _delete(GroupAnnouncement ann) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).accessToken!;
      await _api.deleteAnnouncement(widget.conversationId, ann.id, token);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('groupAnnouncements'.tr()),
        actions: [
          if (widget.canManage)
            IconButton(icon: const Icon(Icons.add), tooltip: 'groupAnnouncementNew'.tr(), onPressed: _create),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('loadFailed'.tr()))
              : _items.isEmpty
                  ? Center(child: Text('groupAnnouncementEmpty'.tr()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ann = _items[index];
                          return Card(
                            child: ListTile(
                              title: Text(ann.title.isEmpty ? ann.content : ann.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (ann.title.isNotEmpty)
                                      Text(ann.content,
                                          maxLines: 3, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${ann.creatorName} · ${_fmt(ann.createdAt)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              isThreeLine: true,
                              trailing: widget.canManage
                                  ? IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(ann),
                                    )
                                  : null,
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(ann.title.isEmpty
                                        ? 'groupAnnouncements'.tr()
                                        : ann.title),
                                    content: SingleChildScrollView(child: Text(ann.content)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: Text('close'.tr()),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Group todos: member-shared checklist with add/toggle/delete.
class GroupTodosPage extends StatefulWidget {
  final int conversationId;

  const GroupTodosPage({super.key, required this.conversationId});

  @override
  State<GroupTodosPage> createState() => _GroupTodosPageState();
}

class _GroupTodosPageState extends State<GroupTodosPage> {
  final ApiService _api = ApiService();
  List<GroupTodo> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final token = Provider.of<AuthService>(context, listen: false).accessToken!;
      final items = await _api.listTodos(widget.conversationId, token);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final token = Provider.of<AuthService>(context, listen: false).accessToken!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('groupTodoNew'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(labelText: 'groupTodoTitle'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('send'.tr())),
        ],
      ),
    );
    if (ok != true || controller.text.trim().isEmpty) return;
    try {
      await _api.createTodo(widget.conversationId, controller.text.trim(), token);
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggle(GroupTodo todo) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).accessToken!;
      await _api.setTodoDone(widget.conversationId, todo.id, !todo.done, token);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _delete(GroupTodo todo) async {
    try {
      final token = Provider.of<AuthService>(context, listen: false).accessToken!;
      await _api.deleteTodo(widget.conversationId, todo.id, token);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('groupTodos'.tr()),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'groupTodoNew'.tr(), onPressed: _add),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('loadFailed'.tr()))
              : _items.isEmpty
                  ? Center(child: Text('groupTodoEmpty'.tr()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final todo = _items[index];
                          return CheckboxListTile(
                            value: todo.done,
                            onChanged: (_) => _toggle(todo),
                            title: Text(
                              todo.title,
                              style: todo.done
                                  ? TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    )
                                  : null,
                            ),
                            secondary: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => _delete(todo),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Group files: attachments shared into the conversation, newest first.
class GroupFilesPage extends StatefulWidget {
  final int conversationId;

  const GroupFilesPage({super.key, required this.conversationId});

  @override
  State<GroupFilesPage> createState() => _GroupFilesPageState();
}

class _GroupFilesPageState extends State<GroupFilesPage> {
  final ApiService _api = ApiService();
  List<GroupFile> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final token = Provider.of<AuthService>(context, listen: false).accessToken!;
      final items = await _api.listGroupFiles(widget.conversationId, token);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _openFile(GroupFile file) {
    final att = file.attachment;
    if (att.isImage) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPreviewPage(attachment: att),
        ),
      );
    }
    // Non-image files are opened from the originating message; the list
    // still surfaces them (name + size) for reference.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('groupFiles'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('loadFailed'.tr()))
              : _items.isEmpty
                  ? Center(child: Text('groupFilesEmpty'.tr()))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final file = _items[index];
                          final att = file.attachment;
                          final isImage = att.isImage;
                          return ListTile(
                            leading: isImage && att.thumbUrl.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(att.thumbUrl,
                                        width: 44, height: 44, fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(Icons.insert_drive_file_outlined)),
                                  )
                                : Icon(isImage
                                    ? Icons.image_outlined
                                    : Icons.insert_drive_file_outlined),
                            title: Text(
                              att.originalName.isEmpty ? 'fileUnnamed'.tr() : att.originalName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${file.senderName} · ${_fmt(file.createdAt)}'
                              '${att.sizeBytes > 0 ? ' · ${_fmtSize(att.sizeBytes)}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            onTap: isImage ? () => _openFile(file) : null,
                          );
                        },
                      ),
                    ),
    );
  }
}

String _fmt(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
