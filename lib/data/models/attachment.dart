class Attachment {
  final int id;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final String url;
  final String visibility;

  Attachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
    this.visibility = 'public',
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as int,
      originalName: json['original_name'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      url: json['url'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'public',
    );
  }

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
