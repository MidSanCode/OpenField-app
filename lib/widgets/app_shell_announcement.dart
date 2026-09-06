import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:easy_localization/easy_localization.dart';

/// Shows the startup app-announcement dialog once per cold start, after the
/// first frame. Announcements the user dismissed permanently are skipped.
void maybeShowStartupAnnouncement(BuildContext context) {
  // Defer to the end of the frame chain so the shell is fully laid out.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_show(context));
  });
}

Future<void> _show(BuildContext context) async {
  try {
    final api = ApiService();
    final announcements = await api.listAppAnnouncements();
    if (announcements.isEmpty || !context.mounted) return;
    final settings = context.read<SettingsService>();
    final pending = announcements
        .where((a) => !settings.dismissedAnnouncementIds.contains(a.id))
        .toList();
    if (pending.isEmpty || !context.mounted) return;
    final latest = pending.first;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.campaign_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(latest.title)),
          ],
        ),
        content: SingleChildScrollView(child: Text(latest.content)),
        actions: [
          TextButton(
            onPressed: () {
              settings.dismissAnnouncement(latest.id);
              Navigator.of(dialogContext).pop();
            },
            child: Text('announcementDontShow'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              GoRouter.of(context).push('/announcements');
            },
            child: Text('announcementHistory'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('ok'.tr()),
          ),
        ],
      ),
    );
  } catch (_) {
    // Announcements are best-effort; a failed fetch must never block startup.
  }
}
