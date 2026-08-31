class Attachment {
  final int id;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final String url;
  final String thumbUrl;
  final String visibility;

  /// E2EE attachment metadata, populated only for attachments shared in an
  /// encrypted conversation. The server stores the AES-encrypted file bytes;
  /// these fields carry the parameters needed to decrypt them locally (the
  /// group-key version and the GCM nonce) plus the real file's mime/name that
  /// the upload had to mask. Empty strings / nulls for plain attachments.
  final int? cryptoVersion;
  final String cryptoNonce;
  final String originalMime;
  final String realName;

  /// Logical storage bucket the object lives on (server-reported).
  final String bucket;

  /// When the attachment was uploaded (server timestamp).
  final DateTime? createdAt;

  /// Burn-after-view deadline (server timestamp). Set the first time someone
  /// other than the uploader views the attachment; once it passes the server
  /// deletes the object and every client shows the burned placeholder.
  /// Null = not armed (attachment is not on a burn message / never viewed).
  final DateTime? burnAt;

  Attachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
    this.thumbUrl = '',
    this.visibility = 'public',
    this.cryptoVersion,
    this.cryptoNonce = '',
    this.originalMime = '',
    this.realName = '',
    this.bucket = '',
    this.createdAt,
    this.burnAt,
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
      cryptoVersion: json['crypto_version'] is num
          ? (json['crypto_version'] as num).toInt()
          : null,
      cryptoNonce: json['crypto_nonce'] as String? ?? '',
      originalMime: json['original_mime'] as String? ?? '',
      realName: json['real_name'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      burnAt: json['burn_at'] is String
          ? DateTime.tryParse(json['burn_at'] as String)
          : null,
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
      if (cryptoVersion != null) 'crypto_version': cryptoVersion,
      if (cryptoNonce.isNotEmpty) 'crypto_nonce': cryptoNonce,
      if (originalMime.isNotEmpty) 'original_mime': originalMime,
      if (realName.isNotEmpty) 'real_name': realName,
    };
  }

  /// A copy marked as E2EE-encrypted. The server only ever sees the ciphertext
  /// URL, so the original name/mime are recovered from [name]/[mime] for local
  /// rendering after decryption.
  Attachment withCrypto({
    required int version,
    required String nonce,
    required String mime,
    required String name,
  }) {
    return Attachment(
      id: id,
      originalName: name,
      mimeType: mime,
      sizeBytes: sizeBytes,
      url: url,
      thumbUrl: '',
      visibility: visibility,
      cryptoVersion: version,
      cryptoNonce: nonce,
      originalMime: mime,
      realName: name,
    );
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

  /// True when the attachment's file bytes were AES-encrypted before upload
  /// (only possible in E2EE conversations). Such attachments must be decrypted
  /// locally before they can be previewed or opened.
  bool get isEncrypted => cryptoVersion != null && cryptoNonce.isNotEmpty;

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

  /// True once the burn-after-view deadline has passed: the server has (or
  /// will within one sweep tick) deleted the object, so render the burned
  /// placeholder instead of the media.
  bool isBurned(DateTime now) => burnAt != null && !burnAt!.isAfter(now);

  /// Seconds left before the burn-after-view deadline, or null when unarmed /
  /// already burned.
  int? secondsToBurn(DateTime now) {
    if (burnAt == null) return null;
    final diff = burnAt!.difference(now).inSeconds;
    return diff > 0 ? diff : null;
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
