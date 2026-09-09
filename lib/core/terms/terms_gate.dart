import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// First-launch terms-of-use gate: shows a non-dismissible agreement dialog
/// on the first app open, linking to the full agreement page. The user must
/// agree before continuing; declining closes the app. The acceptance is
/// persisted in shared_preferences so the dialog never returns.
class TermsGate {
  TermsGate._();

  static const String _acceptedKey = 'terms_accepted_v1';

  /// The public agreement page opened from the dialog.
  static const String agreementUrl =
      'https://terms.msc-studio.eu.cc/agreement/openfield-use-agreement';

  /// Whether the user has already accepted the terms.
  static Future<bool> isAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_acceptedKey) ?? false;
  }

  /// Persists the user's acceptance.
  static Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_acceptedKey, true);
  }

  /// Shows the agreement dialog when the terms were not accepted yet.
  ///
  /// [context] must be below the MaterialApp (post-first-frame). Returns
  /// once the user has agreed (or immediately when already accepted). When
  /// the user declines, the app exits after a confirmation.
  static Future<void> ensureAccepted(BuildContext context) async {
    if (await isAccepted()) return;
    if (!context.mounted) return;

    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('termsTitle'.tr()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('termsBody'.tr()),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _openAgreement(dialogContext),
                  child: Text(
                    'termsLink'.tr(),
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: Theme.of(dialogContext).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('termsDecline'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('termsAgree'.tr()),
            ),
          ],
        ),
      ),
    );

    if (agreed == true) {
      await _accept();
      return;
    }

    // Declined: confirm, then exit the app.
    if (!context.mounted) return;
    final reallyQuit = await showDialog<bool>(
      context: context,
      builder: (quitContext) => AlertDialog(
        title: Text('termsQuitTitle'.tr()),
        content: Text('termsQuitBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(quitContext).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(quitContext).pop(true),
            child: Text('termsQuitConfirm'.tr()),
          ),
        ],
      ),
    );
    if (reallyQuit == true) {
      await SystemNavigator.pop();
    } else if (context.mounted) {
      // User backed out of quitting — ask again.
      await ensureAccepted(context);
    }
  }

  /// Opens the full agreement in the external browser; falls back to an
  /// in-app error snack when no browser is available (e.g. some desktops).
  static Future<void> _openAgreement(BuildContext context) async {
    final uri = Uri.parse(agreementUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('termsLinkFailed'.tr())),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('termsLinkFailed'.tr())),
        );
      }
    }
  }
}
