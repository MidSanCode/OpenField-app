import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:openfield/data/services/media_cache_store.dart';

/// dart:io-backed media cache: URL-hashed files under the app-support
/// directory, pruned oldest-first to [maxDiskBytes].
class MediaCacheStoreImpl implements MediaCacheStore {
  Directory? _dir;

  static String _hash(String url) =>
      sha256.convert(utf8.encode(url)).toString();

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'media_cache'));
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  @override
  Future<Uint8List?> load(String url) async {
    final file = File(p.join((await _cacheDir()).path, _hash(url)));
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      // Corrupt/partial file: treat as a miss and re-download.
      return null;
    }
  }

  @override
  Future<void> save(String url, Uint8List bytes) async {
    try {
      final file = File(p.join((await _cacheDir()).path, _hash(url)));
      await file.writeAsBytes(bytes);
      unawaitedPrune();
    } catch (_) {
      // Cache writes are best-effort; the image already loaded fine.
    }
  }

  /// Deletes the oldest files until the on-disk cache fits [maxDiskBytes].
  Future<void> unawaitedPrune() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final files = dir.listSync(followLinks: false).whereType<File>().toList();
      var total = 0;
      for (final f in files) {
        total += f.lengthSync();
      }
      if (total <= maxDiskBytes) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files) {
        if (total <= maxDiskBytes) break;
        final len = f.lengthSync();
        try {
          await f.delete();
          total -= len;
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// Upper bound for the on-disk cache (bytes); mirrors MediaCache's constant
/// so the pruning loop does not need a dependency back on the cache.
const int maxDiskBytes = 300 * 1024 * 1024;
