import 'dart:typed_data';

import 'package:openfield/data/services/media_cache_store.dart';

/// Web placeholder: the browser sandbox has no dart:io filesystem, so the
/// disk tier is skipped entirely — MediaCache's in-memory LRU is the only
/// layer on web.
class MediaCacheStoreImpl implements MediaCacheStore {
  /// Always returns null: web has no disk tier, so every lookup is a cache
  /// miss and callers fall through to the network.
  @override
  Future<Uint8List?> load(String url) async => null;

  /// No-op: without dart:io there is nowhere to persist bytes, so saves are
  /// silently dropped (the in-memory LRU tier is unaffected).
  @override
  Future<void> save(String url, Uint8List bytes) async {}
}
