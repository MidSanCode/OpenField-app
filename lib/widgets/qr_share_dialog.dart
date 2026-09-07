import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

/// Shared dialog that renders an app deep link (`openfield://user/<id>` or
/// `openfield://group/<id>`) as a scannable QR code, used for the personal
/// account QR and the group invite QR. Scanning it with the in-app scanner
/// opens the profile or offers to join the group.
class QrShareDialog extends StatelessWidget {
  /// The deep-link payload encoded into the QR image.
  final String data;
  /// Dialog heading shown above the QR image.
  final String title;

  const QrShareDialog({super.key, required this.data, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 220,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'qrShareHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('close'.tr()),
        ),
      ],
    );
  }
}
