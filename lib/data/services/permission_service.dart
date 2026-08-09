import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests the runtime permissions the app relies on once at launch:
/// notifications (Android 13+ / iOS) and photo library access (used by the
/// image picker for profile pictures, posts and group avatars).
///
/// Network access (INTERNET) is a normal permission granted at install time and
/// needs no runtime prompt. Native permission dialogs are shown by the OS
/// itself, so their copy is controlled by AndroidManifest.xml / Info.plist
/// rather than the app's translations. Denials are non-fatal: the app keeps
/// working, and the user can still grant permissions later from system settings.
class PermissionService {
  PermissionService._();

  /// Requests the required permissions. No-op on web and desktop platforms,
  /// which have no equivalent runtime prompts.
  static Future<void> requestOnLaunch() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final requests = <Permission>[
      Permission.notification,
      // iOS: photo library is needed by the image picker. Android 13+ uses the
      // system photo picker (no permission); on older Android this maps to
      // READ_EXTERNAL_STORAGE and triggers a dialog.
      if (defaultTargetPlatform == TargetPlatform.iOS)
        Permission.photos
      else
        Permission.storage,
    ];

    for (final permission in requests) {
      try {
        final status = await permission.request();
        if (kDebugMode) {
          debugPrint('[permission] ${permission.toString()} -> $status');
        }
      } catch (e) {
        // Never crash the launch if a permission plugin call fails on an
        // unusual platform or OS version.
        if (kDebugMode) {
          debugPrint('[permission] request failed: $e');
        }
      }
    }
  }
}
