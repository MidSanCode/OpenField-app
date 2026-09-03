import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'package:openfield/data/services/media_cache_store.dart';

/// A small memory + (on native platforms) disk cache for network media.
///
/// URLs are hashed into file names inside the app-support directory on IO
/// platforms, so images (avatars, banners, attachment thumbs) survive app
/// restarts and offline sessions without re-downloading. On web the disk
/// tier is unavailable (no dart:io) and the in-memory LRU is the only layer.
/// On an HTTP failure a [NetworkImageLoadException] is thrown so the existing
/// error placeholders in [Image.network] error builders keep working
/// unchanged.
class MediaCache {
  MediaCache._();

  /// Shared instance; all media loading funnels through it.
  static final MediaCache instance = MediaCache._();

  /// Upper bound for the in-memory decoded cache (bytes).
  static const int maxMemoryBytes = 50 * 1024 * 1024;

  /// Minimum gap between two network downloads of the same URL. Layout churn
  /// (window resize, heavy scrolling) rebuilds image widgets in waves; the
  /// throttle keeps that from hot-looping the server for one URL.
  static const Duration networkCooldown = Duration(seconds: 3);

  final http.Client _client = http.Client();

  final MediaCacheStore _store = MediaCacheStoreImpl();

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
    final disk = await _store.load(url);
    if (disk != null) {
      _storeMemory(url, disk);
      return disk;
    }

    // Throttle: the same URL is requested again and again during layout churn
    // (window resize, scrolling). Never hot-loop the server for it - serve the
    // bytes we fetched within [networkCooldown] and only re-download once the
    // window elapses.
    final lastDownload = _lastDownload[url];
    if (lastDownload != null &&
        DateTime.now().difference(lastDownload) < networkCooldown) {
      final mem = _memory[url];
      if (mem != null) return mem;
    }

    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw NetworkImageLoadException(
        statusCode: resp.statusCode,
        uri: Uri.parse(url),
      );
    }
    final bytes = resp.bodyBytes;
    _lastDownload[url] = DateTime.now();
    _storeMemory(url, bytes);
    unawaited(_store.save(url, bytes));
    return bytes;
  }

  // When each URL was last fetched from the network, used to enforce the
  // [networkCooldown] above.
  final Map<String, DateTime> _lastDownload = {};

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
}
