import 'dart:typed_data';

import 'package:openfield/data/services/media_cache_store.dart';

/// Web placeholder: the browser sandbox has no dart:io filesystem, so the
/// disk tier is skipped entirely — MediaCache's in-memory LRU is the only
/// layer on web.
class MediaCacheStoreImpl implements MediaCacheStore {
  @override
  Future<Uint8List?> load(String url) async => null;

  @override
  Future<void> save(String url, Uint8List bytes) async {}
}
