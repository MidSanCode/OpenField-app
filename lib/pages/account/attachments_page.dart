import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/media/media_preview_page.dart';
import 'package:openfield/widgets/attachment_view.dart';

class AttachmentsPage extends StatefulWidget {
  const AttachmentsPage({super.key});

  @override
  State<AttachmentsPage> createState() => _AttachmentsPageState();
}

class _AttachmentsPageState extends State<AttachmentsPage> {
  final ApiService _apiService = ApiService();
  List<Attachment> _attachments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _apiService.listMyAttachments(authService.accessToken!);
      if (!mounted) return;
      setState(() {
        _attachments = items;
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

  Future<void> _delete(Attachment att) async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteAttachmentConfirm),
        content: Text(att.originalName),
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
    if (confirmed != true) return;
    try {
      await _apiService.deleteAttachment(att.id, authService.accessToken!);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myAttachments)),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.loadFailed),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (_attachments.isEmpty) {
      return Center(child: Text(l10n.noAttachments));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _attachments.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.4,
        ),
        itemBuilder: (context, index) {
          final att = _attachments[index];
          return _buildTile(context, att, () => _openAttachment(context, att), () => _delete(att));
        },
      ),
    );
  }

  void _openAttachment(BuildContext context, Attachment att) {
    if (att.isImage || att.isVideo || att.isAudio) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPreviewPage(attachment: att),
        ),
      );
    } else {
      openAttachmentUrl(context, att.url);
    }
  }
}

Widget _buildTile(BuildContext context, Attachment attachment, VoidCallback onOpen, VoidCallback onDelete) {
  final theme = Theme.of(context);
  IconData iconFor(Attachment att) {
    if (att.isAudio) return Icons.audio_file_outlined;
    if (att.isVideo) return Icons.video_file_outlined;
    if (att.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  return Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: attachment.isImage
                  ? Image.network(
                      attachment.url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stack) => const Icon(
                        Icons.broken_image_outlined,
                        size: 32,
                      ),
                    )
                  : Icon(
                      iconFor(attachment),
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.originalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  formatBytes(attachment.sizeBytes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
