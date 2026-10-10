import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/report.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// The caller's own moderation reports and how each one was handled.
///
/// Filing is done from the content itself (the post/message/user menus); this
/// page is the read-back view, mirroring the server's `GET /reports/mine`.
class MyReportsPage extends StatefulWidget {
  const MyReportsPage({super.key});

  @override
  State<MyReportsPage> createState() => _MyReportsPageState();
}

class _MyReportsPageState extends State<MyReportsPage> {
  final ApiService _api = ApiService();
  List<Report> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'loginWithOIDC'.tr();
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final reports = await _api.listMyReports(token);
      if (mounted) {
        setState(() {
          _reports = reports;
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

  /// Localized name of the kind of content a report points at. An unknown
  /// value (a newer server) falls back to the raw string rather than blank.
  String _targetLabel(String targetType) {
    switch (targetType) {
      case ReportTarget.post:
        return 'reportTargetPost'.tr();
      case ReportTarget.message:
        return 'reportTargetMessage'.tr();
      case ReportTarget.user:
        return 'reportTargetUser'.tr();
      default:
        return targetType;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case ReportStatus.pending:
        return 'reportStatusPending'.tr();
      case ReportStatus.reviewed:
        return 'reportStatusReviewed'.tr();
      case ReportStatus.dismissed:
        return 'reportStatusDismissed'.tr();
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('myReports'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: Text('retry'.tr())),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _reports.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text('myReportsEmpty'.tr())),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _reports.length,
                      itemBuilder: (context, index) =>
                          _ReportTile(report: _reports[index], host: this),
                    ),
            ),
    );
  }
}

/// One report row: the target, the reason, the outcome and, once resolved, the
/// reviewer's note.
class _ReportTile extends StatelessWidget {
  final Report report;
  final _MyReportsPageState host;

  const _ReportTile({required this.report, required this.host});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = report.isPending;
    final statusColor = pending
        ? theme.colorScheme.primary
        : report.isReviewed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return ListTile(
      isThreeLine: true,
      leading: Icon(
        pending ? Icons.hourglass_empty : Icons.flag_outlined,
        color: pending ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${host._targetLabel(report.targetType)} #${report.targetId}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              host._statusLabel(report.status),
              style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            _formatDate(report.createdAt.toLocal()),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          // Only a resolved report carries an operator note; showing the field
          // while it is pending would just be an empty line.
          if (report.reviewNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${report.reviewerUsername}: ${report.reviewNote}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact relative timestamp, matching the format [PostCard]/[ReplyTile] use
/// so a report row reads the same as the content it points at.
String _formatDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
