class Attachment {
  final int id;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final String url;
  final String thumbUrl;
  final String visibility;

  Attachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
    this.thumbUrl = '',
    this.visibility = 'public',
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    return Attachment(
      id: id is int ? id : (id is num ? id.toInt() : int.tryParse('$id') ?? 0),
      originalName: json['original_name'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      sizeBytes: json['size_bytes'] is num ? (json['size_bytes'] as num).toInt() : 0,
      url: json['url'] as String? ?? '',
      thumbUrl: json['thumb_url'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'public',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'original_name': originalName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'url': url,
      'thumb_url': thumbUrl,
      'visibility': visibility,
    };
  }

  /// The URL to load for a compact preview; falls back to the original when no
  /// thumbnail exists.
  String get previewUrl => thumbUrl.isNotEmpty ? thumbUrl : url;

  bool get isImage => _matches('image/', {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic'});
  bool get isAudio => _matches('audio/', {'mp3', 'wav', 'ogg', 'aac', 'm4a', 'flac', 'opus'});
  bool get isVideo => _matches('video/', {'mp4', 'webm', 'mov', 'mkv', 'avi', 'm4v'});
  bool get isText => _matches('text/', {'txt', 'md', 'csv'});
  bool get isBinary => !isImage && !isAudio && !isVideo && !isText;
  bool get isPublic => visibility == 'public';
  bool get isPrivate => visibility == 'private';
  bool get isRestricted => visibility == 'restricted';

  /// True when the mime type starts with [prefix], or when the stored mime type
  /// is generic (e.g. application/octet-stream) but the URL/name extension
  /// matches a known type — this covers older uploads stored without a real
  /// content type.
  bool _matches(String prefix, Set<String> extensions) {
    if (mimeType.startsWith(prefix)) return true;
    if (mimeType.isNotEmpty && !_isGenericMime) return false;
    final ext = _extensionFromUrl.toLowerCase();
    return extensions.contains(ext);
  }

  bool get _isGenericMime =>
      mimeType.isEmpty ||
      mimeType == 'application/octet-stream' ||
      mimeType == 'application/octet stream';

  String get _extensionFromUrl {
    final path = url.contains('?') ? url.split('?').first : url;
    final name = originalName.isNotEmpty ? originalName : path;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1) : '';
  }
}
