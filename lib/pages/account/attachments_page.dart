import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';

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
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _attachments.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final att = _attachments[index];
          return ListTile(
            leading: att.isImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      att.url,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const Icon(Icons.image_outlined),
                    ),
                  )
                : const Icon(Icons.insert_drive_file_outlined),
            title: Text(att.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_formatBytes(att.sizeBytes)),
            trailing: IconButton(
              onPressed: () => _delete(att),
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.delete,
            ),
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
