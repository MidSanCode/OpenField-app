import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A small disk + memory cache for network media.
///
/// URLs are hashed into file names inside the app-support directory, so images
/// (avatars, banners, attachment thumbs) survive app restarts and offline
/// sessions without re-downloading. On an HTTP failure a
/// [NetworkImageLoadException] is thrown so the existing error placeholders in
/// [Image.network] error builders keep working unchanged.
class MediaCache {
  MediaCache._();

  /// Shared instance; all media loading funnels through it.
  static final MediaCache instance = MediaCache._();

  /// Upper bound for the on-disk cache (bytes).
  static const int maxDiskBytes = 300 * 1024 * 1024;

  /// Upper bound for the in-memory decoded cache (bytes).
  static const int maxMemoryBytes = 50 * 1024 * 1024;

  final http.Client _client = http.Client();

  Directory? _dir;

  // ---- in-memory decoded cache (LRU) ----
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  int _memoryBytes = 0;

  // In-flight downloads are deduplicated so concurrent widgets sharing one URL
  // only hit the network once.
  final Map<String, Future<Uint8List>> _inflight = {};

  /// Returns the decoded bytes for [url], from memory, disk or the network in
  /// that order. Throws [NetworkImageLoadException] when the server responds
  /// with a non-2xx status.
  Future<Uint8List> loadBytes(String url) async {
    final mem = _memory[url];
    if (mem != null) {
      _touchMemory(url);
      return mem;
    }
    final existing = _inflight[url];
    if (existing != null) return existing;

    final future = _load(url);
    _inflight[url] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(url);
    }
  }

  Future<Uint8List> _load(String url) async {
    final dir = await _cacheDir();
    final file = File(p.join(dir.path, _hash(url)));

    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        _storeMemory(url, bytes);
        return bytes;
      } catch (_) {
        // Corrupt/partial file: fall through and re-download.
      }
    }

    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw NetworkImageLoadException(
        statusCode: resp.statusCode,
        uri: Uri.parse(url),
      );
    }
    final bytes = resp.bodyBytes;
    _storeMemory(url, bytes);
    unawaited(_writeDisk(file, bytes));
    return bytes;
  }

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'media_cache'));
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<void> _writeDisk(File file, Uint8List bytes) async {
    try {
      await file.writeAsBytes(bytes);
      await _pruneDisk();
    } catch (_) {
      // Cache writes are best-effort; the image already loaded fine.
    }
  }

  /// Deletes the oldest files until the on-disk cache fits [maxDiskBytes].
  Future<void> _pruneDisk() async {
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

  void _storeMemory(String url, Uint8List bytes) {
    _memory.remove(url);
    _memory[url] = bytes;
    _memoryBytes += bytes.lengthInBytes;
    while (_memoryBytes > maxMemoryBytes && _memory.isNotEmpty) {
      final oldest = _memory.keys.first;
      final removed = _memory.remove(oldest);
      if (removed != null) _memoryBytes -= removed.lengthInBytes;
    }
  }

  void _touchMemory(String url) {
    final bytes = _memory.remove(url);
    if (bytes == null) return;
    _memory[url] = bytes;
  }

  static String _hash(String url) =>
      sha256.convert(utf8.encode(url)).toString();
}
