import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import '../../core/config/app_config.dart';
import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/check.dart';
import '../models/consent_request.dart';
import '../models/conversation.dart';
import '../models/post.dart';
import '../models/post_reply.dart';
import '../models/user.dart';
import '../models/wallet.dart';
import '../models/task.dart';
import '../models/transfer.dart';
import '../models/membership.dart';

/// Error raised when an API request fails, carrying the HTTP status code when
/// the server responded, or null for network/parse failures.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  /// Renders as `[<status>] <message>` when the server responded with a
  /// status code so callers that print the exception (snackbars, debug logs,
  /// the red bubble on a failed message) can see the HTTP code at a glance
  /// without having to fish the raw object out of the catch handler.
  @override
  String toString() =>
      statusCode != null ? '[$statusCode] $message' : message;
}

/// HTTP client that logs every request/response to the console and stamps every
/// request with a descriptive User-Agent.
class LoggingClient extends http.BaseClient {
  final http.Client _inner;

  LoggingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['User-Agent'] = userAgent();
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      stopwatch.stop();
      _logApi(
        '${request.method} ${request.url} -> ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      return response;
    } catch (e) {
      stopwatch.stop();
      _logApi(
        '${request.method} ${request.url} -> ERROR ${e.runtimeType} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

/// Platform label embedded in the User-Agent (web-safe).
String _uaPlatform() {
  if (kIsWeb) return 'Web';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isLinux) return 'Linux';
  return 'Unknown';
}

/// The User-Agent sent with every request, e.g. `OpenField-app(Windows) 1.0.0 (1)`.
String userAgent() {
  final version = AppConfig.versionLabel;
  return version.isEmpty
      ? 'OpenField-app(${_uaPlatform()})'
      : 'OpenField-app(${_uaPlatform()}) $version';
}

void _logApi(String message) {
  try {
    debugPrint('[API] $message');
  } catch (_) {}
}

/// Safely decodes a JSON map, returning null when the body is not a JSON object.
Map<String, dynamic>? _decodeMap(http.Response response) {
  try {
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) return data;
  } catch (_) {}
  return null;
}

/// Infers the MIME type for an uploaded file from its extension so attachments
/// are correctly classified (e.g. images previewed instead of shown as files).
MediaType _mediaTypeFor(String filePath) {
  final ext = filePath.split('.').last.toLowerCase();
  const map = <String, String>{
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'mkv': 'video/x-matroska',
    'avi': 'video/x-msvideo',
    'm4v': 'video/x-m4v',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'aac': 'audio/aac',
    'm4a': 'audio/mp4',
    'flac': 'audio/flac',
    'opus': 'audio/opus',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'pdf': 'application/pdf',
    // OpenField E2EE ciphertext container (.ofe): AES-GCM encrypted file
    // bytes uploaded for encrypted conversations.
    'ofe': 'application/x-openfield-encrypted',
  };
  return MediaType.parse(map[ext] ?? 'application/octet-stream');
}

/// Public variant of the upload mime guesser, used by callers that need the
/// inferred content type for their own purposes (e.g. recording the real mime
/// of an attachment before it is encrypted).
String mimeTypeForPath(String filePath) => _mediaTypeFor(filePath).toString();

class ApiService {
  static const String defaultBaseUrl = 'https://api.openfield.eu.cc/api/v1';
  static const String defaultServerHost = 'https://api.openfield.eu.cc';
  static String _baseUrl = defaultBaseUrl;
  static String _serverHost = defaultServerHost;
  final http.Client _client;

  /// The active API base URL. Updated when the user changes the server host in
  /// settings. Read dynamically per request so changes apply immediately.
  static String get baseUrl => _baseUrl;

  /// The normalized server host the API is currently pointing at. Sessions are
  /// bound to this value (see [AuthService.switchServer]).
  static String get serverHost => _serverHost;

  ApiService({http.Client? client})
      : _client = client ?? LoggingClient(http.Client());

  /// Applies a new server host (e.g. `http://localhost:8080`). Setting a null
  /// or empty value resets to the default. Malformed input (missing scheme,
  /// unparsable URL) silently falls back to the default rather than breaking
  /// every subsequent request.
  static void setServerHost(String? host) {
    var value = host?.trim().replaceAll(RegExp(r'/+$'), '') ?? '';
    if (value.isEmpty) {
      _serverHost = defaultServerHost;
      _baseUrl = '$_serverHost/api/v1';
      return;
    }
    if (!value.contains('://')) {
      value = 'http://$value';
    }
    Uri? uri;
    try {
      uri = Uri.parse(value);
    } catch (_) {
      _serverHost = defaultServerHost;
      _baseUrl = '$_serverHost/api/v1';
      return;
    }
    if (!uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _serverHost = defaultServerHost;
      _baseUrl = '$_serverHost/api/v1';
      return;
    }
    _serverHost = value;
    _baseUrl = '$_serverHost/api/v1';
  }

  Map<String, String> _headers({String? token, bool json = true}) {
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (json) headers['Content-Type'] = 'application/json';
    return headers;
  }

  String _decodeError(http.Response response, String fallback) {
    var message = fallback;
    var jsonBody = false;
    final body = response.body;
    try {
      final decoded = jsonDecode(body);
      jsonBody = true;
      if (decoded is Map && decoded['error'] is String) {
        final err = decoded['error'] as String;
        if (err.isNotEmpty) message = err;
      } else if (decoded is String && decoded.isNotEmpty) {
        message = decoded;
      }
    } catch (_) {
      // Non-JSON body (e.g. an HTML error page from a proxy or old server).
      final trimmed = body.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('<')) {
        message = trimmed.length > 200 ? '${trimmed.substring(0, 200)}...' : trimmed;
      }
    }
    if (_isUnsupportedFeature(response.statusCode, message, jsonBody)) {
      return 'unsupportedFeature'.tr();
    }
    return message;
  }

  /// Status codes that indicate the server does not understand or implement
  /// the request (as opposed to a genuine application-level rejection like a
  /// validation error or a missing resource that the server knows about).
  static const Set<int> _unsupportedStatuses = {404, 405, 406, 501, 503};

  /// Maps a generic "route/feature not found or not implemented" response to a
  /// user-friendly "server does not support this feature" message, while
  /// keeping application-level errors (e.g. "conversation not found") intact.
  bool _isUnsupportedFeature(int status, String message, bool jsonBody) {
    if (!_unsupportedStatuses.contains(status)) return false;
    // A non-JSON error page almost always comes from a proxy or an old
    // deployment that does not know the route.
    if (!jsonBody) return message.isNotEmpty;
    final m = message.trim().toLowerCase();
    return m == 'not found' ||
        m == 'method not allowed' ||
        m == 'not implemented' ||
        m == 'route not found' ||
        m == 'service unavailable';
  }

  // ---- Guarded HTTP helpers ----
  //
  // Every request goes through [_guard] so network-level failures (offline,
  // DNS, timeouts, TLS) surface as [ApiException] instead of raw exceptions
  // that pages are not expecting, and nothing crashes the app.

  Future<http.Response> _get(Uri url, {Map<String, String>? headers}) =>
      _guard(() => _client.get(url, headers: headers));

  Future<http.Response> _post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _guard(() => _client.post(url, headers: headers, body: body));

  Future<http.Response> _put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _guard(() => _client.put(url, headers: headers, body: body));

  Future<http.Response> _delete(Uri url, {Map<String, String>? headers}) =>
      _guard(() => _client.delete(url, headers: headers));

  Future<http.Response> _send(http.BaseRequest request) =>
      _guard(() async => http.Response.fromStream(await _client.send(request)));

  Future<http.Response> _guard(Future<http.Response> Function() run) async {
    try {
      return await run();
    } on ApiException {
      rethrow;
    } on SocketException {
      throw ApiException(null, 'networkError'.tr());
    } on http.ClientException {
      throw ApiException(null, 'networkError'.tr());
    } on TimeoutException {
      throw ApiException(null, 'requestTimeout'.tr());
    } on IOException {
      throw ApiException(null, 'networkError'.tr());
    } on FormatException {
      throw ApiException(null, 'requestFailed'.tr());
    } catch (_) {
      throw ApiException(null, 'requestFailed'.tr());
    }
  }

  // ---- Auth ----

  /// Requests the OIDC authorize URL. On web builds [flow] should be 'web' so
  /// the server redirects back to the web origin instead of the openfield://
  /// custom scheme that a browser cannot open.
  Future<String> getOIDCLoginUrl({String flow = 'app'}) async {
    final response =
        await _get(Uri.parse('$baseUrl/auth/oidc/login?flow=$flow'));
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final url = data['auth_url'];
      if (url is String && url.isNotEmpty) return url;
      throw ApiException(response.statusCode, 'Invalid OIDC login URL');
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to get OIDC login URL'));
  }

  Future<Map<String, dynamic>> oidcCallback(String code) async {
    final response = await _get(
      Uri.parse('$baseUrl/auth/oidc/callback?code=$code'),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(response.statusCode, 'OIDC callback failed');
  }

  /// Mints a short-lived single-use WebSocket connection ticket. Browsers
  /// cannot set custom headers during the upgrade handshake, and putting the
  /// long-lived JWT in the URL would leak it into proxy/access logs, so the
  /// realtime client exchanges its Bearer token for this one-time ticket and
  /// then connects with `?ticket=` instead.
  Future<Map<String, dynamic>> createWsTicket(String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/ws'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null && data['ticket'] is String) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to create connection ticket'));
  }

  /// Starts the OIDC account-binding flow for the authenticated user.
  Future<String> getOIDCBindUrl(String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/oidc/bind'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final url = data['auth_url'];
      if (url is String && url.isNotEmpty) return url;
      throw ApiException(response.statusCode, 'Invalid OIDC bind URL');
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to start OIDC binding'));
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers(),
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Login failed'));
  }

  /// Exchanges a refresh token for a fresh access token. The refresh token is
  /// rotated server-side, so the response carries a new one.
  Future<Map<String, dynamic>> refreshAccessToken(String refreshToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: _headers(),
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Token refresh failed'));
  }

  Future<User> register(String username, String nickname, String accessToken, {String bio = ''}) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'username': username, 'nickname': nickname, 'bio': bio}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return User.fromJson(data);
    }
    if (response.statusCode == 409) {
      throw ApiException(response.statusCode, 'Username already taken');
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Registration failed'));
  }

  // ---- Account ----

  Future<User> getCurrentUser(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return User.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to get user'));
  }

  Future<User> getUser(int userId, {String? token}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/$userId'),
      headers: _headers(token: token, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return User.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to get user'));
  }

  Future<List<User>> searchUsers(String accessToken, String query, {int limit = 20}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/search?q=${Uri.encodeQueryComponent(query)}&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['users'];
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((u) => User.fromJson(u))
            .toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to search users'));
  }

  /// Returns the current user's effective permission keys and group names.
  Future<Map<String, dynamic>> getMyPermissions(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/me/permissions'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to get permissions'));
  }

  Future<User> updateProfile(String accessToken, {String? username, String? nickname, String? bio}) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (nickname != null) body['nickname'] = nickname;
    if (bio != null) body['bio'] = bio;
    final response = await _put(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers(token: accessToken),
      body: jsonEncode(body),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return User.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to update profile'));
  }

  /// Updates the current user's display-name styling (color, optional gradient
  /// end color, optional animated flag) and the reserved avatar frame, subject
  /// to their membership tier's caps. Returns the updated name-style fields.
  ///
  /// [colors] and [direction] are the multi-color gradient fields used by
  /// Lv.3+ members; the legacy [color]/[colorTo] pair is sent alongside for
  /// backward compatibility with older servers.
  Future<Map<String, dynamic>> updateNameStyle(
    String accessToken, {
    required String color,
    String colorTo = '',
    bool animated = false,
    String avatarFrame = '',
    List<String> colors = const [],
    String direction = '',
  }) async {
    final body = <String, dynamic>{
      'color': color,
      'color_to': colorTo,
      'dynamic': animated,
      'avatar_frame': avatarFrame,
      'colors': colors,
      'direction': direction,
    };
    final response = await _put(
      Uri.parse('$baseUrl/users/me/name-style'),
      headers: _headers(token: accessToken),
      body: jsonEncode(body),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to update name style'));
  }

  Future<User> uploadAvatar(String filePath, String accessToken) async {
    final data = await _uploadMultipart('$baseUrl/users/me/avatar', filePath, accessToken);
    return User.fromJson(data);
  }

  Future<User> uploadBanner(String filePath, String accessToken) async {
    final data = await _uploadMultipart('$baseUrl/users/me/banner', filePath, accessToken);
    return User.fromJson(data);
  }

  // ---- Storage ----

  Future<Attachment> uploadAttachment(
    String filePath,
    String accessToken, {
    String visibility = 'public',
    ValueChanged<double>? onProgress,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/attachments'));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      contentType: _mediaTypeFor(filePath),
    ));
    request.fields['visibility'] = visibility;
    final response = await _sendMultipartProgressed(request, onProgress);
    final data = _decodeMap(response);
    if ((response.statusCode == 200 || response.statusCode == 201) && data != null) {
      return Attachment.fromJson(data);
    }
    throw ApiException(
        response.statusCode,
        _decodeError(response, 'Upload failed (${response.statusCode})'));
  }

  /// Sends a multipart request while reporting byte-level upload progress as
  /// a fraction in [0, 1]. Falls back to the plain path when no [onProgress]
  /// is given. The body is re-piped through a counting stream so progress
  /// reflects actual bytes handed to the socket.
  Future<http.Response> _sendMultipartProgressed(
    http.MultipartRequest request,
    ValueChanged<double>? onProgress,
  ) async {
    if (onProgress == null) return _send(request);

    final byteStream = request.finalize();
    final total = request.contentLength;
    var sent = 0;

    final streamed = http.StreamedRequest(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..persistentConnection = request.persistentConnection
      ..headers.addAll(request.headers)
      ..contentLength = total;

    byteStream
        .map((chunk) {
          sent += chunk.length;
          if (total > 0) onProgress(sent / total);
          return chunk;
        })
        .listen(streamed.sink.add,
            onError: streamed.sink.addError,
            onDone: streamed.sink.close,
            cancelOnError: true);

    try {
      final response = await _client.send(streamed);
      return await http.Response.fromStream(response);
    } on http.ClientException catch (e) {
      throw ApiException(0, e.message);
    }
  }

  /// Streams [url] to the local file [savePath], reporting progress. Returns
  /// the save path. Not supported on the web build (no file system).
  Future<String> downloadToFile(
    String url,
    String savePath, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    if (kIsWeb) {
      throw ApiException(0, 'Downloads are not supported on the web build');
    }
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Download failed (${response.statusCode})');
    }
    final sink = File(savePath).openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, response.contentLength);
      }
      await sink.flush();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (File(savePath).existsSync()) File(savePath).deleteSync();
      rethrow;
    } finally {
      await sink.close();
    }
    return savePath;
  }

  /// Per-bucket storage statistics for the signed-in user.
  Future<StorageUsage> fetchStorageUsage(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/storage/usage'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return StorageUsage.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load usage'));
  }

  /// Default chunk size (4 MiB) used for large-file uploads.
  static const int chunkSizeBytes = 4 * 1024 * 1024;

  /// Threshold above which a file is uploaded in chunks instead of a single
  /// multipart request, so large files support resuming after interruptions.
  static const int chunkedUploadThreshold = 16 * 1024 * 1024;

  /// Uploads a file, transparently switching to chunked upload + resume for
  /// large files. [onProgress] reports a fraction in [0, 1] when provided.
  ///
  /// Before sending, the file's SHA-256 is checked against the cloud: when an
  /// identical file already exists the upload is skipped and the existing link
  /// is returned. (Images whose GPS metadata is stripped server-side may miss
  /// the local hash match and fall through to a normal upload, where the server
  /// deduplicates by the sanitized bytes.)
  Future<Attachment> uploadAttachmentSmart(
    String filePath,
    String accessToken, {
    String visibility = 'public',
    ValueChanged<double>? onProgress,
  }) async {
    final existing = await _findAttachmentByHash(
      await _fileSha256(filePath),
      accessToken,
    );
    if (existing != null) {
      onProgress?.call(1);
      return existing;
    }

    final file = File(filePath);
    final size = await file.length();
    if (size < chunkedUploadThreshold) {
      return uploadAttachment(filePath, accessToken,
          visibility: visibility, onProgress: onProgress);
    }
    return _uploadAttachmentChunked(file, size, accessToken, visibility: visibility, onProgress: onProgress);
  }

  /// Computes the hex-encoded SHA-256 of a file without loading it fully into
  /// memory, so even large files can be hashed for upload deduplication.
  Future<String> _fileSha256(String filePath) async {
    final file = File(filePath);
    final raf = await file.open();
    try {
      var digests = <Digest>[];
      final runSink = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((chunks) {
          digests = chunks;
        }),
      );
      const chunkSize = 4 * 1024 * 1024;
      while (true) {
        final chunk = await raf.read(chunkSize);
        if (chunk.isEmpty) break;
        runSink.add(chunk);
      }
      runSink.close();
      return digests.single.toString();
    } finally {
      await raf.close();
    }
  }

  /// Looks up an existing attachment with the given content hash. Returns null
  /// when the cloud has no such file (or the lookup itself fails), in which
  /// case the caller should upload normally.
  Future<Attachment?> _findAttachmentByHash(String hash, String accessToken) async {
    try {
      final response = await _get(
        Uri.parse('$baseUrl/attachments/by-hash/$hash'),
        headers: _headers(token: accessToken, json: false),
      );
      if (response.statusCode == 200) {
        final data = _decodeMap(response);
        if (data != null) return Attachment.fromJson(data);
      }
    } catch (_) {
      // Network/hash mismatch: fall through to a normal upload.
    }
    return null;
  }

  Future<Attachment> _uploadAttachmentChunked(
    File file,
    int fileSize,
    String accessToken, {
    required String visibility,
    ValueChanged<double>? onProgress,
  }) async {
    final totalChunks = (fileSize / chunkSizeBytes).ceil();
    final mimeType = _mediaTypeFor(file.path).toString();

    final init = await _post(
      Uri.parse('$baseUrl/attachments/chunk/init'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'filename': file.uri.pathSegments.last,
        'size': fileSize,
        'total_chunks': totalChunks,
        'mime_type': mimeType,
        'visibility': visibility,
      }),
    );
    final initData = _decodeMap(init);
    if (init.statusCode != 201 || initData == null) {
      throw ApiException(init.statusCode, _decodeError(init, 'Failed to start upload'));
    }
    final uploadId = initData['upload_id'] as String;

    // Resume: query which chunks already landed on the server.
    final uploaded = <int>{};
    final status = await _get(
      Uri.parse('$baseUrl/attachments/chunk/$uploadId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (status.statusCode == 200) {
      final statusData = _decodeMap(status);
      final list = statusData?['uploaded'];
      if (list is List) {
        uploaded.addAll(list.whereType<int>());
      }
    }

    final raf = await file.open();
    var completedBytes = 0;
    // Chunks restored from a previous session count towards progress.
    for (final index in uploaded) {
      final start = (index - 1) * chunkSizeBytes;
      completedBytes += (start + chunkSizeBytes > fileSize)
          ? fileSize - start
          : chunkSizeBytes;
    }
    try {
      for (var index = 1; index <= totalChunks; index++) {
        if (uploaded.contains(index)) {
          onProgress?.call(completedBytes / fileSize);
          continue;
        }
        final start = (index - 1) * chunkSizeBytes;
        await raf.setPosition(start);
        final length = (start + chunkSizeBytes > fileSize)
            ? fileSize - start
            : chunkSizeBytes;
        final chunk = await raf.read(length);
        // raf.read is permitted to return short reads, but the server only
        // counts chunks by index, so a partial chunk upload would still be
        // recorded as "present" with the wrong size and trip the dedup hash
        // check on complete(). Fail loudly instead of uploading a partial.
        if (chunk.length < length) {
          throw ApiException(
            null,
            'short read on chunk $index (got ${chunk.length}/$length bytes)',
          );
        }

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/attachments/chunk/$uploadId/$index'),
        );
        request.headers['Authorization'] = 'Bearer $accessToken';
        request.files.add(http.MultipartFile.fromBytes('chunk', chunk));
        // A transient network blip on any single chunk would otherwise surface
        // as a hard 409 "missing chunks" at the complete() step. Retry the
        // chunk up to 3 times with a short backoff before giving up.
        const maxAttempts = 3;
        Object? lastError;
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          try {
            await _sendMultipartProgressed(request, (fraction) {
              onProgress?.call(
                  (completedBytes + fraction * length) / fileSize);
            });
            lastError = null;
            break;
          } catch (e) {
            lastError = e;
            if (attempt == maxAttempts) rethrow;
            await Future<void>.delayed(
                Duration(milliseconds: 250 * attempt));
          }
        }
        if (lastError != null) throw lastError;
        completedBytes += length;
        onProgress?.call(completedBytes / fileSize);
      }
    } finally {
      raf.close();
    }

    final complete = await _post(
      Uri.parse('$baseUrl/attachments/chunk/$uploadId/complete'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'filename': file.uri.pathSegments.last,
        'size': fileSize,
        'total_chunks': totalChunks,
        'mime_type': mimeType,
        'visibility': visibility,
      }),
    );
    final data = _decodeMap(complete);
    if ((complete.statusCode == 200 || complete.statusCode == 201) && data != null) {
      onProgress?.call(1);
      return Attachment.fromJson(data);
    }
    throw ApiException(complete.statusCode, _decodeError(complete, 'Failed to finish upload'));
  }

  Future<List<Attachment>> listMyAttachments(String accessToken, {int limit = 100}) async {
    final response = await _get(
      Uri.parse('$baseUrl/attachments?limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['attachments'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((a) => Attachment.fromJson(a)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load attachments'));
  }

  Future<void> deleteAttachment(int attachmentId, String accessToken) async {
    final response = await _delete(
      Uri.parse('$baseUrl/attachments/$attachmentId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to delete attachment'));
    }
  }

  Future<Map<String, dynamic>> _uploadMultipart(String url, String filePath, String accessToken) async {
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final response = await _send(request);
    final data = _decodeMap(response);
    if ((response.statusCode == 200 || response.statusCode == 201) && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode,
        _decodeError(response, 'Upload failed (${response.statusCode})'));
  }

  // ---- Service health ----

  /// Aggregated backend health from the gateway (public, no token needed):
  /// `all_healthy` plus a per-service map of status/latency/details.
  Future<Map<String, dynamic>> getServicesHealth() async {
    final response = await _get(
      Uri.parse('$baseUrl/health'),
      headers: _headers(json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    if (response.statusCode == 503 && data != null) return data;
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to check services'));
  }

  // ---- Checks (red packets) ----

  /// Escrows [amountCoins] into a new check with [shares] shares expiring
  /// after [expiresInHours]. The payment PIN authorizes the charge.
  Future<Check> createCheck(
    String accessToken, {
    required double amountCoins,
    required int shares,
    String mode = 'random',
    int expiresInHours = 24,
    required String pin,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/checks'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'amount': amountCoins,
        'shares': shares,
        'mode': mode,
        'expires_in_hours': expiresInHours,
        'pin': pin,
      }),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 201 && data != null) {
      return Check.fromJson(data['check'] as Map<String, dynamic>);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to create check'));
  }

  Future<Check> getCheck(int checkId, {String? token}) async {
    final response = await _get(
      Uri.parse('$baseUrl/checks/$checkId'),
      headers: _headers(token: token, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Check.fromJson(data['check'] as Map<String, dynamic>);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load check'));
  }

  Future<CheckClaim> claimCheck(String accessToken, int checkId) async {
    final response = await _post(
      Uri.parse('$baseUrl/checks/$checkId/claim'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return CheckClaim.fromJson(data['claim'] as Map<String, dynamic>);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to claim check'));
  }

  // ---- Posts ----

  /// Loads posts with optional advanced filters: a content keyword, an author
  /// (user id or name substring) and an inclusive date range. All combine
  /// with AND server-side.
  Future<List<Post>> getPosts({
    int page = 1,
    int limit = 20,
    String? token,
    String? query,
    int? authorId,
    String? author,
    DateTime? from,
    DateTime? to,
    String? tag,
  }) async {
    final params = <String>[
      'page=$page',
      'limit=$limit',
      if (query != null && query.trim().isNotEmpty)
        'q=${Uri.encodeQueryComponent(query.trim())}',
      if (authorId != null && authorId > 0) 'author_id=$authorId',
      if (author != null && author.trim().isNotEmpty)
        'author=${Uri.encodeQueryComponent(author.trim())}',
      if (from != null)
        'from=${(from.millisecondsSinceEpoch ~/ 1000)}',
      if (to != null)
        'to=${(to.millisecondsSinceEpoch ~/ 1000) + 86399}',
      if (tag != null && tag.trim().isNotEmpty)
        'tag=${Uri.encodeQueryComponent(tag.trim())}',
    ];
    final response = await _get(
      Uri.parse('$baseUrl/posts?${params.join('&')}'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final postsList = data?['posts'];
      if (postsList is List) {
        return postsList.whereType<Map<String, dynamic>>().map((p) => Post.fromJson(p)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load posts'));
  }

  Future<Post> getPost(int postId, [String? token]) async {
    final response = await _get(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: token, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Post.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load post'));
  }

  Future<List<Post>> getPostsByUser(int userId, {String? token, int page = 1, int limit = 20}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/$userId/posts?page=$page&limit=$limit'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final postsList = data?['posts'];
      if (postsList is List) {
        return postsList.whereType<Map<String, dynamic>>().map((p) => Post.fromJson(p)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load user posts'));
  }

  Future<Post> createPost(String content, String accessToken,
      {List<int> attachmentIds = const [],
      String visibility = 'public',
      int checkId = 0,
      List<String> tags = const []}) async {
    final response = await _post(
      Uri.parse('$baseUrl/posts'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'content': content,
        'attachment_ids': attachmentIds,
        'visibility': visibility,
        if (checkId > 0) 'check_id': checkId,
        if (tags.isNotEmpty) 'tags': tags,
      }),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 201 && data != null) {
      return Post.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to create post'));
  }

  Future<Post> updatePost(int postId, String content, String accessToken,
      {List<int> attachmentIds = const [], String? visibility}) async {
    final body = <String, dynamic>{
      'content': content,
      'attachment_ids': attachmentIds,
    };
    if (visibility != null) body['visibility'] = visibility;
    final response = await _put(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: accessToken),
      body: jsonEncode(body),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Post.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to update post'));
  }

  Future<void> deletePost(int postId, String accessToken) async {
    final response = await _delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to delete post'));
    }
  }

  /// Tips [amountCoins] coins on a post, authorized by the payment PIN. The
  /// author's wallet receives 95% of the tip.
  Future<Map<String, dynamic>> tipPost(
      int postId, int amountCoins, String accessToken, String pin) async {
    final response = await _post(
      Uri.parse('$baseUrl/posts/$postId/tips'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'amount': amountCoins, 'pin': pin}),
    );
    final data = _decodeMap(response);
    if ((response.statusCode == 200 || response.statusCode == 201) && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to tip post'));
  }

  // ---- Post replies ----

  Future<List<PostReply>> listReplies(int postId, {String? token, int page = 1, int limit = 50}) async {
    final response = await _get(
      Uri.parse('$baseUrl/posts/$postId/replies?page=$page&limit=$limit'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['replies'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((r) => PostReply.fromJson(r)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load replies'));
  }

  Future<PostReply> createReply(int postId, String content, String accessToken,
      {int? parentId, List<int> attachmentIds = const []}) async {
    final response = await _post(
      Uri.parse('$baseUrl/posts/$postId/replies'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'parent_id': parentId, 'attachment_ids': attachmentIds}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 201 && data != null) {
      return PostReply.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to create reply'));
  }

  Future<PostReply> updateReply(int postId, int replyId, String content, String accessToken,
      {List<int> attachmentIds = const []}) async {
    final response = await _put(
      Uri.parse('$baseUrl/posts/$postId/replies/$replyId'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'attachment_ids': attachmentIds}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return PostReply.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to update reply'));
  }

  Future<void> deleteReply(int postId, int replyId, String accessToken) async {
    final response = await _delete(
      Uri.parse('$baseUrl/posts/$postId/replies/$replyId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to delete reply'));
    }
  }

  // ---- Post reactions ----

  Future<Post> reactToPost(int postId, String reaction, String accessToken) async {
    final response = await _put(
      Uri.parse('$baseUrl/posts/$postId/reactions'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'reaction': reaction}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Post.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to set reaction'));
  }

  Future<Post> removePostReaction(int postId, String accessToken) async {
    final response = await _delete(
      Uri.parse('$baseUrl/posts/$postId/reactions'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Post.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to remove reaction'));
  }

  // ---- Favorites ----

  /// Marks a post as favorited by the current user.
  Future<Post> favoritePost(int postId, String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/posts/$postId/favorite'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Post.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to favorite post'));
  }

  /// Removes the current user's favorite from a post.
  Future<Post> unfavoritePost(int postId, String accessToken) async {
    final response = await _delete(
      Uri.parse('$baseUrl/posts/$postId/favorite'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Post.fromJson(data);
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to unfavorite post'));
  }

  /// Marks a reply as favorited by the current user.
  Future<PostReply> favoriteReply(int postId, int replyId, String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/posts/$postId/replies/$replyId/favorite'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return PostReply.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to favorite reply'));
  }

  /// Removes the current user's favorite from a reply.
  Future<PostReply> unfavoriteReply(int postId, int replyId, String accessToken) async {
    final response = await _delete(
      Uri.parse('$baseUrl/posts/$postId/replies/$replyId/favorite'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return PostReply.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to unfavorite reply'));
  }

  /// Lists the current user's favorited posts. [userId] must be the current
  /// user's own id; the server rejects requests for another user's favorites.
  Future<List<Post>> listFavoritePosts(String accessToken, int userId,
      {int page = 1, int limit = 20}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/$userId/favorites/posts?page=$page&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['posts'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((p) => Post.fromJson(p)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load favorite posts'));
  }

  /// Lists the current user's favorited replies. [userId] must be the current
  /// user's own id; the server rejects requests for another user's favorites.
  Future<List<PostReply>> listFavoriteReplies(String accessToken, int userId,
      {int page = 1, int limit = 20}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/$userId/favorites/replies?page=$page&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['replies'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((r) => PostReply.fromJson(r)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load favorite replies'));
  }

  // ---- Follows ----

  Future<void> followUser(int userId, String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/users/$userId/follow'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to follow user'));
    }
  }

  Future<void> unfollowUser(int userId, String accessToken) async {
    final response = await _delete(
      Uri.parse('$baseUrl/users/$userId/follow'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to unfollow user'));
    }
  }

  Future<List<User>> listFollowers(int userId, {String? token, int page = 1, int limit = 50}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/$userId/followers?page=$page&limit=$limit'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['users'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((u) => User.fromJson(u)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load followers'));
  }

  Future<List<User>> listFollowing(int userId, {String? token, int page = 1, int limit = 50}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/$userId/following?page=$page&limit=$limit'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['users'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((u) => User.fromJson(u)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load following'));
  }

  /// Lists the users who mutually follow the given user (friends).
  Future<List<User>> listFriends(int userId, {String? token, int page = 1, int limit = 50}) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/$userId/friends?page=$page&limit=$limit'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['users'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((u) => User.fromJson(u)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load friends'));
  }

  // ---- Wallet ----

  /// Returns the current user's wallet balance and recent transactions.
  Future<Wallet> getWallet(String accessToken, {int page = 1, int limit = 20}) async {
    final response = await _get(
      Uri.parse('$baseUrl/wallet?page=$page&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Wallet.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load wallet'));
  }

  /// Adjusts a user's wallet balance. Positive amounts recharge, negative
  /// amounts deduct. Requires the wallet.manage permission.
  Future<Wallet> adjustWallet(
    String accessToken, {
    required int userId,
    required double amount,
    String? type,
    String? description,
  }) async {
    final body = <String, dynamic>{'user_id': userId, 'amount': amount};
    if (type != null && type.isNotEmpty) body['type'] = type;
    if (description != null && description.isNotEmpty) body['description'] = description;
    final response = await _post(
      Uri.parse('$baseUrl/wallet/adjust'),
      headers: _headers(token: accessToken),
      body: jsonEncode(body),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Wallet.fromJson({'balance': data['balance']});
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to adjust wallet'));
  }

  // ---- Chat: consent requests ----

  Future<List<ConsentRequest>> listConsentRequests(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/consent-requests'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['requests'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((r) => ConsentRequest.fromJson(r)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load requests'));
  }

  Future<Conversation?> acceptConsentRequest(String accessToken, int requestId) async {
    final response = await _post(
      Uri.parse('$baseUrl/consent-requests/$requestId/accept'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final conv = data['conversation'];
      if (conv is Map<String, dynamic>) return Conversation.fromJson(conv);
      return null;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to accept request'));
  }

  Future<void> declineConsentRequest(String accessToken, int requestId) async {
    final response = await _post(
      Uri.parse('$baseUrl/consent-requests/$requestId/decline'),
      headers: _headers(token: accessToken),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to decline request'));
    }
  }

  // ---- Chat: conversations ----

  Future<List<Conversation>> listConversations(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/conversations'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['conversations'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((c) => Conversation.fromJson(c)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load conversations'));
  }

  Future<ConversationDetail> getConversation(String accessToken, int conversationId) async {
    final response = await _get(
      Uri.parse('$baseUrl/conversations/$conversationId'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return ConversationDetail.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load conversation'));
  }

  Future<Conversation> createGroup(String accessToken, String title) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'title': title}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 201 && data != null) {
      return Conversation.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to create group'));
  }

  Future<void> startPrivateChat(
    String accessToken,
    int userId, {
    String message = '',
    bool encrypted = false,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/start'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'user_id': userId,
        'message': message,
        'encrypted': encrypted,
      }),
    );
    if (response.statusCode != 201) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to start chat'));
    }
  }

  Future<void> inviteToGroup(String accessToken, int conversationId, int userId, {String message = ''}) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/invite'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'user_id': userId, 'message': message}),
    );
    if (response.statusCode != 201) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to send invite'));
    }
  }

  Future<void> updateNote(String accessToken, int conversationId, String note) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/note'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'note': note}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update note'));
    }
  }

  Future<void> updateGroupNickname(String accessToken, int conversationId, String nickname) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/group-nickname'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'group_nickname': nickname}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update group nickname'));
    }
  }

  Future<void> markConversationRead(String accessToken, int conversationId, int lastMessageId) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/read'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'last_message_id': lastMessageId}),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to mark as read'));
    }
  }

  Future<void> leaveGroup(String accessToken, int conversationId) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/leave'),
      headers: _headers(token: accessToken),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to leave group'));
    }
  }

  Future<void> removeGroupMember(String accessToken, int conversationId, int userId) async {
    final response = await _delete(
      Uri.parse('$baseUrl/conversations/$conversationId/members/$userId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to remove member'));
    }
  }

  Future<void> deleteConversation(String accessToken, int conversationId) async {
    final response = await _delete(
      Uri.parse('$baseUrl/conversations/$conversationId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to delete conversation'));
    }
  }

  Future<List<Conversation>> fetchPublicGroups(String accessToken, {String query = ''}) async {
    final response = await _get(
      Uri.parse('$baseUrl/conversations/public${query.isNotEmpty ? '?q=${Uri.encodeQueryComponent(query)}' : ''}'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['groups'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((c) => Conversation.fromJson(c)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load public groups'));
  }

  Future<Conversation> joinGroup(String accessToken, int conversationId) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/join'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return Conversation.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to join group'));
  }

  Future<void> updateGroupSettings(String accessToken, int conversationId,
      {required bool isPublic, required bool allowJoin, bool? encrypted}) async {
    final body = <String, dynamic>{'is_public': isPublic, 'allow_join': allowJoin};
    if (encrypted != null) body['encrypted'] = encrypted;
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/settings'),
      headers: _headers(token: accessToken),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update group settings'));
    }
  }

  /// Renames a group conversation (owner only).
  Future<void> updateGroupTitle(
      String accessToken, int conversationId, String title) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/title'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'title': title}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update group title'));
    }
  }

  /// Sets a group conversation's avatar image URL (owner only).
  Future<void> updateGroupAvatar(
      String accessToken, int conversationId, String avatarUrl) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/avatar'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'avatar_url': avatarUrl}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update group avatar'));
    }
  }

  // ---- Chat: E2EE ----

  /// Publishes (or clears) the current user's X25519 public key used to seal
  /// group-key envelopes.
  Future<void> updateE2EEKey(String accessToken, String publicKey) async {
    final response = await _put(
      Uri.parse('$baseUrl/users/me/e2ee-key'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'public_key': publicKey}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update e2ee key'));
    }
  }

  /// Fetches the group-key envelopes stored for a conversation, together with
  /// the current key version.
  Future<Map<String, dynamic>> getE2EEKeys(String accessToken, int conversationId) async {
    final response = await _get(
      Uri.parse('$baseUrl/conversations/$conversationId/e2ee-keys'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load e2ee keys'));
  }

  /// Stores a batch of group-key envelopes keyed by target user id. Returns the
  /// new key version the server assigned.
  Future<int> putE2EEKeys(
    String accessToken,
    int conversationId,
    Map<int, String> envelopes,
  ) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/e2ee-keys'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'envelopes': envelopes.map((k, v) => MapEntry('$k', v)),
      }),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final version = data['version'];
      if (version is int) return version;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to store e2ee keys'));
  }

  Future<void> setMemberRole(String accessToken, int conversationId, int userId, String role) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/members/$userId/role'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'role': role}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update member role'));
    }
  }

  /// Sets the owner/admin-controlled title displayed next to a member's
  /// nickname in the chat. Pass an empty string to clear it.
  Future<void> setMemberTitle(
      String accessToken, int conversationId, int userId, String title) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/members/$userId/title'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'title': title}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update member title'));
    }
  }

  Future<void> muteMember(String accessToken, int conversationId, int userId, int durationMinutes) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/members/$userId/mute'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'duration_minutes': durationMinutes}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to mute member'));
    }
  }

  Future<void> unmuteMember(String accessToken, int conversationId, int userId) async {
    final response = await _delete(
      Uri.parse('$baseUrl/conversations/$conversationId/members/$userId/mute'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to unmute member'));
    }
  }

  Future<void> muteAllMembers(String accessToken, int conversationId, int durationMinutes) async {
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/mute-all'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'duration_minutes': durationMinutes}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to mute group'));
    }
  }

  Future<void> unmuteAllMembers(String accessToken, int conversationId) async {
    final response = await _delete(
      Uri.parse('$baseUrl/conversations/$conversationId/mute-all'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to unmute group'));
    }
  }

  // ---- Chat: messages ----

  Future<List<ChatMessage>> listMessages(
    String accessToken,
    int conversationId, {
    int before = 0,
    int limit = 50,
  }) async {
    final response = await _get(
      Uri.parse('$baseUrl/conversations/$conversationId/messages?before=$before&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['messages'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((m) => ChatMessage.fromJson(m)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load messages'));
  }

  /// Searches chat history in a conversation. All filters are optional and
  /// combined with AND by the server: [query] matches content, [senderId]
  /// restricts the author, [from]/[to] bound the time range inclusively,
  /// [hasAttachments] keeps only messages with files and [fileName] matches
  /// attachment original names. Returns newest-first matches.
  Future<List<ChatMessage>> searchMessages(
    String accessToken,
    int conversationId, {
    String query = '',
    int? senderId,
    DateTime? from,
    DateTime? to,
    bool hasAttachments = false,
    String fileName = '',
    int limit = 50,
  }) async {
    final params = <String, String>{
      if (query.trim().isNotEmpty) 'q': query.trim(),
      if (senderId != null && senderId > 0) 'sender_id': '$senderId',
      if (from != null)
        'from': (from.millisecondsSinceEpoch ~/ 1000).toString(),
      if (to != null) 'to': (to.millisecondsSinceEpoch ~/ 1000).toString(),
      if (hasAttachments || fileName.trim().isNotEmpty) 'has_attachment': 'true',
      if (fileName.trim().isNotEmpty) 'file_name': fileName.trim(),
      'limit': '$limit',
    };
    final qs = params.entries
        .map((e) =>
            '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final response = await _get(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/search?$qs'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['messages'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().map((m) => ChatMessage.fromJson(m)).toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to search messages'));
  }

  Future<ChatMessage> sendChatMessage(
    String accessToken,
    int conversationId,
    String content, {
    int? replyToId,
    List<int> attachmentIds = const [],
    List<int> mentions = const [],
    int checkId = 0,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      'reply_to_id': replyToId,
      'attachment_ids': attachmentIds,
      if (checkId > 0) 'check_id': checkId,
    };
    if (mentions.isNotEmpty) body['mentions'] = mentions;
    final response = await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/messages'),
      headers: _headers(token: accessToken),
      body: jsonEncode(body),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 201 && data != null) {
      return ChatMessage.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to send message'));
  }

  /// Sets the current user's per-conversation notification preference
  /// ('all' | 'mentions' | 'none').
  Future<void> setNotifyLevel(
      String accessToken, int conversationId, String level) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/notify-level'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'level': level}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update notification level'));
    }
  }

  /// Claims the once-per-server-day experience bonus for the current user.
  /// Idempotent: returns {granted: false} when already claimed today.
  Future<Map<String, dynamic>> claimDailyBonus(String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/users/me/claim-daily-bonus'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to claim daily bonus'));
  }

  /// Updates the user's region and display language for server-pushed
  /// notifications.
  Future<void> updateLocale(String accessToken,
      {String region = '', String lang = ''}) async {
    final response = await _put(
      Uri.parse('$baseUrl/users/me/locale'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'region': region, 'lang': lang}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update locale'));
    }
  }

  /// Updates the user's follow-list privacy. When enabled, the followers /
  /// following / friends lists are hidden from everyone else on the server.
  Future<void> updatePrivacy(String accessToken, {required bool hideFollowLists}) async {
    final response = await _put(
      Uri.parse('$baseUrl/users/me/privacy'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'hide_follow_lists': hideFollowLists}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to update privacy'));
    }
  }

  /// Fetches the configured storage buckets with their labels, default quotas,
  /// membership gates and the current user's selected bucket.
  Future<Map<String, dynamic>> listStorageBuckets(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/users/storage-buckets'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to load storage buckets'));
  }

  /// Switches the current user to another storage bucket. Returns the updated
  /// user.
  Future<User> setStorageBucket(String accessToken, String bucket) async {
    final response = await _put(
      Uri.parse('$baseUrl/users/me/storage-bucket'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'bucket': bucket}),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          _decodeError(response, 'Failed to switch storage bucket'));
    }
    final data = _decodeMap(response);
    final user = data?['user'];
    if (user is Map<String, dynamic>) return User.fromJson(user);
    throw ApiException(response.statusCode, 'Invalid response');
  }

  /// Fetches the task catalog with the user's progress, current sign-in streak
  /// and the make-up cost in currency.
  Future<Map<String, dynamic>> listTasks(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/tasks'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load tasks'));
  }

  /// Claims the daily sign-in streak reward. Returns {granted: bool, exp,
  /// currency, streak}.
  Future<Map<String, dynamic>> claimDailyLogin(String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/tasks/daily-login/claim'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to claim daily sign-in'));
  }

  /// Pays the make-up cost to renew the sign-in streak. Returns {granted,
  /// exp, cost, streak}.
  Future<Map<String, dynamic>> makeUpCheckin(String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/tasks/daily-login/makeup'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to make up check-in'));
  }

  /// Fetches the daily-login sign-in calendar: date range, signed days, streak
  /// and make-up cost.
  Future<Map<String, dynamic>> checkinCalendar(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/tasks/daily-login/calendar'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to load sign-in calendar'));
  }

  /// Pays to sign in a specific missed past calendar day ("YYYY-MM-DD").
  /// Returns {granted: bool, date, exp, cost, streak}.
  Future<Map<String, dynamic>> makeupByDate(
      String accessToken, String date) async {
    final response = await _post(
      Uri.parse('$baseUrl/tasks/daily-login/makeup-date'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'date': date}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to make up check-in'));
  }

  /// Sets (or changes) the 6-digit payment PIN.
  Future<void> setPin(String accessToken, String pin) async {
    final response = await _post(
      Uri.parse('$baseUrl/users/me/pin'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'pin': pin}),
    );
    if (response.statusCode == 200) return;
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to set PIN'));
  }

  /// Replaces an existing payment PIN. The current PIN must be presented.
  Future<void> changePin(
      String accessToken, String oldPin, String pin) async {
    final response = await _put(
      Uri.parse('$baseUrl/users/me/pin'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'old_pin': oldPin, 'pin': pin}),
    );
    if (response.statusCode == 200) return;
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to change PIN'));
  }

  /// Verifies a payment PIN against the stored hash.
  Future<bool> verifyPin(String accessToken, String pin) async {
    final response = await _post(
      Uri.parse('$baseUrl/users/me/pin/verify'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'pin': pin}),
    );
    if (response.statusCode == 200) return true;
    return false;
  }

  /// Claims a one-time achievement task reward by its code.
  Future<Map<String, dynamic>> claimTask(String accessToken, String code) async {
    final response = await _post(
      Uri.parse('$baseUrl/tasks/$code/claim'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) return data;
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to claim task'));
  }

  /// Fetches the user's experience history, newest first.
  Future<List<ExpEntry>> listExpHistory(String accessToken, {int limit = 50}) async {
    final response = await _get(
      Uri.parse('$baseUrl/exp/history?limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['entries'];
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => ExpEntry.fromJson(e))
            .toList();
      }
      return const [];
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load exp history'));
  }

  /// Lists incoming or outgoing currency transfers.
  Future<List<Transfer>> listTransfers(String accessToken,
      {String direction = 'incoming', int page = 1, int limit = 20}) async {
    final response = await _get(
      Uri.parse('$baseUrl/transfers?direction=$direction&page=$page&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = _decodeMap(response);
      final list = data?['transfers'];
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((t) => Transfer.fromJson(t))
            .toList();
      }
      return const [];
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to load transfers'));
  }

  /// Creates a transfer to another user. The amount is held from the sender and
  /// only credited to the recipient on acceptance. The 6-digit payment PIN
  /// authorizes the outgoing payment.
  Future<Transfer> createTransfer(String accessToken,
      {required int recipientId,
      required double amount,
      String note = '',
      String pin = ''}) async {
    final response = await _post(
      Uri.parse('$baseUrl/transfers'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'recipient_id': recipientId,
        'amount': amount,
        'note': note,
        'pin': pin,
      }),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final transfer = data['transfer'];
      if (transfer is Map<String, dynamic>) return Transfer.fromJson(transfer);
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to create transfer'));
  }

  /// Accepts a pending incoming transfer, crediting it to the recipient.
  Future<Transfer> acceptTransfer(String accessToken, int id) async {
    final response = await _post(
      Uri.parse('$baseUrl/transfers/$id/accept'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final transfer = data['transfer'];
      if (transfer is Map<String, dynamic>) return Transfer.fromJson(transfer);
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to accept transfer'));
  }

  /// Declines a pending incoming transfer, refunding it to the sender.
  Future<Transfer> declineTransfer(String accessToken, int id) async {
    final response = await _post(
      Uri.parse('$baseUrl/transfers/$id/decline'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final transfer = data['transfer'];
      if (transfer is Map<String, dynamic>) return Transfer.fromJson(transfer);
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to decline transfer'));
  }

  /// Fetches the user's membership state and the purchaseable tier catalog.
  Future<MembershipStatus> getMembership(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/membership'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return MembershipStatus.fromJson(data);
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to load membership'));
  }

  /// Purchases a membership tier with wallet coins, authorized by the 6-digit
  /// payment PIN. Returns the updated membership status.
  Future<MembershipStatus> purchaseMembership(
      String accessToken, int level, String pin) async {
    final response = await _post(
      Uri.parse('$baseUrl/membership/purchase'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'level': level, 'pin': pin}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return MembershipStatus.fromJson(data);
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to purchase membership'));
  }

  /// Toggles the user's membership automatic renewal. Enabling pre-authorizes
  /// future wallet charges, so it requires the payment PIN; disabling only
  /// needs the token. Returns the updated membership status.
  Future<MembershipStatus> setMembershipAutoRenew(
      String accessToken, bool enabled, String pin) async {
    final response = await _put(
      Uri.parse('$baseUrl/membership/auto-renew'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'enabled': enabled, 'pin': pin}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return MembershipStatus.fromJson(data);
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to update auto-renew'));
  }

  /// Fetches the server's public capability matrix (open, no auth).
  Future<Map<String, dynamic>> getCapabilities() async {
    final response = await _get(
      Uri.parse('$baseUrl/capabilities'),
      headers: _headers(json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load capabilities'));
  }

  /// Lists the current user's membership purchase/renewal/upgrade history,
  /// newest first. Returns the page items.
  Future<List<MembershipPurchase>> getMembershipPurchases(
      String accessToken,
      {int page = 1, int limit = 20}) async {
    final response = await _get(
      Uri.parse('$baseUrl/membership/purchases?page=$page&limit=$limit'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final items = (data['purchases'] as List?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(MembershipPurchase.fromJson)
          .toList();
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to load membership purchases'));
  }

  Future<ChatMessage> editChatMessage(String accessToken, int conversationId, int messageId, String content) async {
    final response = await _put(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return ChatMessage.fromJson(data);
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to edit message'));
  }

  Future<void> deleteChatMessage(String accessToken, int conversationId, int messageId) async {
    final response = await _delete(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to delete message'));
    }
  }

  /// Announces that the current user is typing in a conversation. Fire-and-forget.
  Future<void> sendTyping(String accessToken, int conversationId) async {
    await _post(
      Uri.parse('$baseUrl/conversations/$conversationId/typing'),
      headers: _headers(token: accessToken, json: false),
    );
  }

  // ---- plugins (store) ----

  /// Lists published plugins from the store. Works signed-out; a token only
  /// personalizes the response.
  Future<List<StorePlugin>> listStorePlugins([String? token]) async {
    final response = await _get(
      Uri.parse('$baseUrl/plugins'),
      headers: _headers(token: token, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final items = (data['plugins'] as List?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(StorePlugin.fromJson)
          .toList();
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load plugins'));
  }

  /// Downloads one plugin bundle. Requires sign-in so installs are auditable
  /// per user.
  Future<List<int>> downloadStorePlugin(String accessToken, String id) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/plugins/$id/download'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to download plugin'));
  }

  // ---- bots ----

  /// Registers a new bot account owned by the current user. The returned map
  /// carries `user` (full profile) and `token` — the static ofb_ API token
  /// the bot uses for every request. It is shown exactly once.
  Future<Map<String, dynamic>> registerBot(
      String accessToken, String username, String nickname) async {
    final response = await _post(
      Uri.parse('$baseUrl/bots'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'username': username, 'nickname': nickname}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 201 && data != null) {
      return data;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to create bot'));
  }

  /// Lists the bots owned by the current user.
  Future<List<BotAccount>> listBots(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/bots'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final items = (data['bots'] as List?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(BotAccount.fromJson)
          .toList();
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to load bots'));
  }

  /// Replaces a bot's API token; the old one stops working immediately.
  Future<String> regenerateBotToken(String accessToken, int botId) async {
    final response = await _post(
      Uri.parse('$baseUrl/bots/$botId/regenerate'),
      headers: _headers(token: accessToken, json: false),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null && data['token'] is String) {
      return data['token'] as String;
    }
    throw ApiException(
        response.statusCode, _decodeError(response, 'Failed to regenerate token'));
  }

  /// Deletes a bot account together with its content.
  Future<void> deleteBot(String accessToken, int botId) async {
    final response = await _delete(
      Uri.parse('$baseUrl/bots/$botId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException(
          response.statusCode, _decodeError(response, 'Failed to delete bot'));
    }
  }


// === Presence / sessions / deletion / notifications / QR ===

  /// Sends a heartbeat to keep the current user marked as online.
  Future<void> sendHeartbeat(String accessToken) async {
    await _post(
      Uri.parse('$baseUrl/users/me/heartbeat'),
      headers: _headers(token: accessToken),
    );
  }

  /// Asks the server to schedule account deletion; the user can cancel within
  /// the grace window via [cancelDeletion].
  Future<void> requestDeletion(String accessToken) async {
    await _post(
      Uri.parse('$baseUrl/users/me/deletion-request'),
      headers: _headers(token: accessToken),
    );
  }

  /// Cancels a previously requested deletion.
  Future<void> cancelDeletion(String accessToken) async {
    await _delete(
      Uri.parse('$baseUrl/users/me/deletion-request'),
      headers: _headers(token: accessToken),
    );
  }

  /// Lists the devices the current user is signed in on.
  Future<List<SessionDevice>> listSessions(String accessToken) async {
    final response = await _get(
      Uri.parse('$baseUrl/auth/sessions'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      final items = (data['sessions'] as List?) ?? const [];
      return items
          .map((e) => SessionDevice.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to list sessions'));
  }

  /// Revokes one of the user's own sessions by id.
  Future<void> deleteSession(String accessToken, int sessionId) async {
    final response = await _delete(
      Uri.parse('$baseUrl/auth/sessions/$sessionId'),
      headers: _headers(token: accessToken),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          _decodeError(response, 'Failed to revoke session'));
    }
  }

  /// Fetches the notification inbox.
  Future<NotificationPage> listNotifications(
    String accessToken, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _get(
      Uri.parse('$baseUrl/notifications?limit=$limit&offset=$offset'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return NotificationPage.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to list notifications'));
  }

  /// Marks notifications as read; pass an empty list to clear every unread
  /// item in one shot.
  Future<int> markNotificationsRead(
    String accessToken, {
    List<int> ids = const [],
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/notifications/read'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'ids': ids}),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return ((data['marked_read'] as num?) ?? 0).toInt();
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to mark notifications read'));
  }

  /// Kicks off a QR login handshake: the caller shows the returned code as a
  /// QR code; an already-authenticated device scans and approves it; this
  /// device polls [pollQrLogin] until it sees the access/refresh tokens.
  Future<String> createQrLogin(String accessToken) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/qr'),
      headers: _headers(token: accessToken),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return data['code']?.toString() ?? '';
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to create qr code'));
  }

  /// Polls a pending QR login. Returns the current state; when status flips
  /// to confirmed the access/refresh tokens are ready for the requesting
  /// device to adopt.
  Future<QrLoginResult> pollQrLogin(String code) async {
    final response = await _get(
      Uri.parse('$baseUrl/auth/qr/$code'),
    );
    final data = _decodeMap(response);
    if (response.statusCode == 200 && data != null) {
      return QrLoginResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw ApiException(response.statusCode,
        _decodeError(response, 'Failed to poll qr code'));
  }

  /// Approves a pending QR login. Called by an authenticated device after it
  /// scanned the code on the requesting device.
  Future<void> approveQrLogin(String accessToken, String code) async {
    final response = await _post(
      Uri.parse('$baseUrl/auth/qr/$code/approve'),
      headers: _headers(token: accessToken),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          _decodeError(response, 'Failed to approve qr login'));
    }
  }
}

/// One bot account as listed by GET /bots (owner-facing view).
class BotAccount {
  final int id;
  final String username;
  final String nickname;
  final String avatarUrl;
  final DateTime? createdAt;

  /// When the current API token was issued (regeneration resets it).
  final DateTime? tokenCreatedAt;

  const BotAccount({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatarUrl = '',
    this.createdAt,
    this.tokenCreatedAt,
  });

  String get displayName => nickname.isNotEmpty ? nickname : username;

  factory BotAccount.fromJson(Map<String, dynamic> json) {
    return BotAccount(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      username: json['username']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString() ?? '',
      createdAt: _parseDate(json['created_at']),
      tokenCreatedAt: _parseDate(json['token_created_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }
}

/// One plugin listed by the store (server-side row of the catalog).
class StorePlugin {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;

  /// Raw permission keys requested by the bundle's manifest.
  final List<String> permissions;
  final String minAppVersion;
  final bool verified;
  final int downloads;

  const StorePlugin({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    this.permissions = const [],
    this.minAppVersion = '',
    this.verified = false,
    this.downloads = 0,
  });

  factory StorePlugin.fromJson(Map<String, dynamic> json) {
    String asString(Object? v) => v?.toString() ?? '';
    final perms = json['permissions'];
    return StorePlugin(
      id: asString(json['id']),
      name: asString(json['name']),
      version: asString(json['version']),
      author: asString(json['author']),
      description: asString(json['description']),
      permissions: perms is List ? perms.map(asString).toList() : const [],
      minAppVersion: asString(json['min_app_version']),
      verified: json['verified'] == true,
      downloads: json['downloads'] is num ? (json['downloads'] as num).toInt() : 0,
    );
  }
}

/// Storage statistics for the signed-in user, from GET /storage/usage.
class StorageUsage {
  final int totalCount;
  final int totalBytes;

  /// Optional quota block; null when the server runs without quotas.
  final int? quotaBaseBytes;
  final int? quotaBonusBytes;
  final int? quotaEffectiveBytes;

  /// Per-bucket breakdown sorted by size (server-side).
  final List<BucketUsage> buckets;

  const StorageUsage({
    required this.totalCount,
    required this.totalBytes,
    this.quotaBaseBytes,
    this.quotaBonusBytes,
    this.quotaEffectiveBytes,
    this.buckets = const [],
  });

  factory StorageUsage.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    final bucketList = json['buckets'];
    final quota = json['quota'];
    return StorageUsage(
      totalCount: asInt(json['total_count']),
      totalBytes: asInt(json['total_bytes']),
      quotaBaseBytes:
          quota is Map<String, dynamic> && quota['base_bytes'] is num
              ? (quota['base_bytes'] as num).toInt()
              : null,
      quotaBonusBytes:
          quota is Map<String, dynamic> && quota['bonus_bytes'] is num
              ? (quota['bonus_bytes'] as num).toInt()
              : null,
      quotaEffectiveBytes:
          quota is Map<String, dynamic> && quota['effective_bytes'] is num
              ? (quota['effective_bytes'] as num).toInt()
              : null,
      buckets: bucketList is List
          ? bucketList
              .whereType<Map<String, dynamic>>()
              .map(BucketUsage.fromJson)
              .toList()
          : const [],
    );
  }

  double get quotaFraction =>
      quotaEffectiveBytes != null && quotaEffectiveBytes! > 0
          ? (totalBytes / quotaEffectiveBytes!).clamp(0.0, 1.0)
          : 0.0;
}

/// Attachment count and size for one storage bucket.
class BucketUsage {
  final String bucket;
  final int count;
  final int sizeBytes;

  const BucketUsage({
    required this.bucket,
    required this.count,
    required this.sizeBytes,
  });

  factory BucketUsage.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return BucketUsage(
      bucket: json['bucket']?.toString() ?? '',
      count: asInt(json['count']),
      sizeBytes: asInt(json['size_bytes']),
    );
  }
}

/// A device the current user is logged in on.
class SessionDevice {
  final int id;
  final String deviceLabel;
  final String lastIp;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  SessionDevice({
    required this.id,
    required this.deviceLabel,
    required this.lastIp,
    required this.createdAt,
    required this.lastUsedAt,
  });

  factory SessionDevice.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return SessionDevice(
      id: ((json['id'] as num?) ?? 0).toInt(),
      deviceLabel: json['device_label']?.toString() ?? '',
      lastIp: json['last_ip']?.toString() ?? '',
      createdAt: parse(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastUsedAt: parse(json['last_used_at']),
    );
  }
}

/// A page of notifications plus the unread badge count.
class NotificationPage {
  final List<AppNotification> items;
  final int total;
  final int unread;

  NotificationPage({required this.items, required this.total, required this.unread});

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final raw = (json['notifications'] as List?) ?? const [];
    return NotificationPage(
      items: raw
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total: ((json['total'] as num?) ?? raw.length).toInt(),
      unread: ((json['unread'] as num?) ?? 0).toInt(),
    );
  }
}

/// A single inbox entry.
class AppNotification {
  final int id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
  });

  bool get unread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    DateTime parse(Object? v) {
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    return AppNotification(
      id: ((json['id'] as num?) ?? 0).toInt(),
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: parse(json['created_at']),
      readAt: json['read_at'] == null ? null : parse(json['read_at']),
    );
  }
}

/// Polling response for the QR login handshake. While the code is pending
/// the caller keeps polling; once status flips to confirmed the access and
/// refresh tokens are ready for the requesting device to adopt.
class QrLoginResult {
  final String code;
  final String status; // pending | confirmed | expired
  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final int? refreshExpiresIn;

  QrLoginResult({
    required this.code,
    required this.status,
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.refreshExpiresIn,
  });

  bool get isConfirmed => status == 'confirmed' && accessToken != null;

  factory QrLoginResult.fromJson(Map<String, dynamic> json) {
    return QrLoginResult(
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      expiresIn: (json['expires_in'] as num?)?.toInt(),
      refreshExpiresIn: (json['refresh_expires_in'] as num?)?.toInt(),
    );
  }
}
