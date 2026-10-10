import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/report.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// Longest reason the server accepts; the counter here matches it.
const int reportReasonMaxLength = 500;

/// Turns a failed report submission into a message the reporter can act on.
/// The guards the server enforces each have their own wording, so a duplicate
/// or a throttled submission does not read like a generic failure.
String reportErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.statusCode) {
      case 409:
        return 'reportAlreadyFiled'.tr();
      case 429:
        return 'reportRateLimited'.tr();
      case 404:
        return 'reportTargetGone'.tr();
      case 400:
        return error.message;
    }
    return error.message;
  }
  return error.toString();
}

/// Opens the report sheet for one piece of content and files the report.
///
/// [title] is the localized heading ("举报帖子" / "举报消息" / "举报用户"),
/// [targetType] one of the [ReportTarget] values and [targetId] the id of the
/// reported row. [preview] is an optional excerpt of the reported content,
/// shown so the reporter can confirm they picked the right item.
///
/// Returns true when the report was accepted, so callers can refresh.
Future<bool> showReportDialog(
  BuildContext context, {
  required String title,
  required String targetType,
  required int targetId,
  String? preview,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final filed = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _ReportDialog(title: title, targetType: targetType, targetId: targetId, preview: preview),
  );
  if (filed == true) {
    messenger.showSnackBar(SnackBar(content: Text('reportSubmitted'.tr())));
  }
  return filed == true;
}

/// The report form: a required reason and a submit action that stays disabled
/// until the reason is usable.
class _ReportDialog extends StatefulWidget {
  final String title;
  final String targetType;
  final int targetId;
  final String? preview;

  const _ReportDialog({
    required this.title,
    required this.targetType,
    required this.targetId,
    this.preview,
  });

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final ApiService _api = ApiService();
  final TextEditingController _reason = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// The reason is required; an all-whitespace one is not a reason.
  bool get _canSubmit => !_submitting && _reason.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('loginWithOIDC'.tr())));
      return;
    }
    final reason = _reason.text.trim();
    setState(() => _submitting = true);
    try {
      await _api.createReport(widget.targetType, widget.targetId, reason, token);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.preview != null && widget.preview!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.preview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: reportReasonMaxLength,
            maxLines: 4,
            minLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'reportReasonLabel'.tr(),
              hintText: 'reportReasonHint'.tr(),
              border: const OutlineInputBorder(),
            ),
          ),
          Text(
            'reportHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('confirm'.tr()),
        ),
      ],
    );
  }
}
