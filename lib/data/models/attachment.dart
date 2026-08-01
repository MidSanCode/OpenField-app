class Attachment {
  final int id;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final String url;

  Attachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as int,
      originalName: json['original_name'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      url: json['url'] as String? ?? '',
    );
  }

  bool get isImage => mimeType.startsWith('image/');

  bool get isAudio => mimeType.startsWith('audio/');

  bool get isVideo => mimeType.startsWith('video/');

  bool get isText => mimeType.startsWith('text/');

  bool get isBinary =>
      !isImage && !isAudio && !isVideo && !isText;
}
