// Web-only implementation of URL history helpers. Kept behind a conditional
// import so the app never loads it on non-web platforms.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Strips the query string from the current browser URL, removing the OAuth
/// tokens after they have been consumed by the app.
void clearUrlQueryParams() {
  final uri = Uri.base;
  final stripped = uri.replace(queryParameters: {});
  html.window.history.replaceState(null, '', stripped.toString());
}
