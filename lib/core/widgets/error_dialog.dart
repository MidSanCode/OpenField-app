import 'package:flutter/material.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/l10n/app_localizations.dart';

/// Shows an AlertDialog describing an API failure. When the error is an
/// [ApiException] with an HTTP status code, the code is shown in the title.
Future<void> showApiErrorDialog(BuildContext context, Object error,
    {String? title}) async {
  final l10n = AppLocalizations.of(context);
  final statusCode =
      error is ApiException ? error.statusCode : null;
  final message =
      error is ApiException ? error.message : error.toString();

  final dialogTitle = title ??
      (statusCode != null ? '${l10n?.error ?? 'Error'} (HTTP $statusCode)' : l10n?.error ?? 'Error');

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(dialogTitle),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n?.ok ?? 'OK'),
        ),
      ],
    ),
  );
}
