import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../data/services/media_cache.dart';
/// An [ImageProvider] that loads bytes through [MediaCache] instead of the
/// default [NetworkImage] transport.
///
/// Keep [url] (and everything the cache key derives from) immutable so a
/// rebuilt widget deduplicates on an already-loaded provider. Drop-in for
/// `Image.network(url)` via `Image(image: CachedNetworkImageProvider(url))`;
/// existing `loadingBuilder` / `errorBuilder` callbacks keep working, and HTTP
/// failures surface as [NetworkImageLoadException] exactly like the built-in
/// network image.
class CachedNetworkImageProvider extends ImageProvider<CachedNetworkImageProvider> {
  const CachedNetworkImageProvider(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  @override
  Future<CachedNetworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedNetworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => [DiagnosticsProperty('url', key.url)],
    );
  }

  Future<ui.Codec> _loadAsync(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await MediaCache.instance.loadBytes(key.url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CachedNetworkImageProvider &&
        other.url == url &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => '$runtimeType("$url", scale: $scale)';
}
