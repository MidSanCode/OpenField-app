import 'dart:typed_data';

/// Platform dispatch for the media cache's disk layer.
///
/// On IO platforms media bytes persist in the app-support directory; on web
/// there is no dart:io (and path_provider throws MissingPluginException), so
/// the store degrades to in-memory only.
export 'media_cache_store_stub.dart'
    if (dart.library.io) 'media_cache_store_io.dart';

/// Disk persistence for media bytes. Keyed by URL; failures are best-effort
/// and never surface to callers.
abstract class MediaCacheStore {
  /// Returns cached bytes for [url], or null on miss/error.
  Future<Uint8List?> load(String url);

  /// Persists [bytes] for [url]; implementers must swallow all errors.
  Future<void> save(String url, Uint8List bytes);
}
