import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/media_image.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
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
  StorageUsage? _usage;
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
      final results = await Future.wait<dynamic>([
        _apiService.listMyAttachments(authService.accessToken!),
        _apiService.fetchStorageUsage(authService.accessToken!),
      ]);
      if (!mounted) return;
      setState(() {
        _attachments = results[0] as List<Attachment>;
        _usage = results[1] as StorageUsage;
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('deleteAttachmentConfirm'.tr()),
        content: Text(att.originalName),
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

    return Scaffold(
      appBar: AppBar(title: Text('myAttachments'.tr())),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
            ElevatedButton(onPressed: _load, child: Text('retry'.tr())),
          ],
        ),
      );
    }
    if (_attachments.isEmpty) {
      return Center(child: Text('noAttachments'.tr()));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _UsageCard(usage: _usage),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.4,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final att = _attachments[index];
                  return _buildTile(context, att,
                      () => _openAttachment(context, att), () => _delete(att));
                },
                childCount: _attachments.length,
              ),
            ),
          ),
        ],
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: attachment.isImage
                      ? MediaImage(
                          url: attachment.url,
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          iconFor(attachment),
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _DeleteButton(onPressed: onDelete),
                ),
              ],
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

/// A small translucent delete button overlaid on an attachment tile.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.delete_outline,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Storage statistics header: total files/size, optional quota bar and the
/// per-bucket usage breakdown served by GET /storage/usage.
class _UsageCard extends StatelessWidget {
  final StorageUsage? usage;

  const _UsageCard({this.usage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (usage == null) {
      // Usage endpoint unavailable: degrade to a plain totals card computed
      // from the visible attachment list is skipped; show nothing.
      return const SizedBox.shrink();
    }
    final u = usage!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.donut_small_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('usageTitle'.tr(), style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('usageTotalCount'.tr(args: ['${u.totalCount}']),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatBytes(u.totalBytes),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (u.quotaEffectiveBytes != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                        '/ ${formatBytes(u.quotaEffectiveBytes!)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurfaceVariant)),
                  ),
                ],
              ],
            ),
            if (u.quotaEffectiveBytes != null &&
                u.quotaEffectiveBytes! > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: u.quotaFraction,
                  minHeight: 6,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              if ((u.quotaBonusBytes ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('usageBonus'.tr(args: [
                    formatBytes(u.quotaBonusBytes!),
                  ]),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
            if (u.buckets.isNotEmpty) ...[
              const Divider(height: 24),
              ...u.buckets.map((b) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            b.bucket.isEmpty ? 'default' : b.bucket,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text('usageBucketFiles'.tr(args: ['${b.count}']),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(width: 12),
                        Text(formatBytes(b.sizeBytes),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
