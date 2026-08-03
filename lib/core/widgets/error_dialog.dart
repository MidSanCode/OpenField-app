import 'package:flutter/material.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:easy_localization/easy_localization.dart';

/// Shows an AlertDialog describing an API failure. When the error is an
/// [ApiException] with an HTTP status code, the code is shown in the title.
Future<void> showApiErrorDialog(BuildContext context, Object error,
    {String? title}) async {
  final statusCode =
      error is ApiException ? error.statusCode : null;
  final message =
      error is ApiException ? error.message : error.toString();

  final dialogTitle = title ??
      (statusCode != null ? '${'error'.tr()} (HTTP $statusCode)' : 'error'.tr());

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(dialogTitle),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('ok'.tr()),
        ),
      ],
    ),
  );
}
