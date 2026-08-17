import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import '../models/attachment.dart';
import '../models/chat_message.dart';
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

  @override
  String toString() => message;
}

/// HTTP client that logs every request/response to the console.
class LoggingClient extends http.BaseClient {
  final http.Client _inner;

  LoggingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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
  };
  return MediaType.parse(map[ext] ?? 'application/octet-stream');
}

class ApiService {
  static const String defaultBaseUrl = 'https://of-api.msc-studio.eu.cc/api/v1';
  static const String defaultServerHost = 'https://of-api.msc-studio.eu.cc';
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

  Future<String> getOIDCLoginUrl() async {
    final response = await _get(Uri.parse('$baseUrl/auth/oidc/login'));
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

  Future<Attachment> uploadAttachment(String filePath, String accessToken, {String visibility = 'public'}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/attachments'));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      contentType: _mediaTypeFor(filePath),
    ));
    request.fields['visibility'] = visibility;
    final response = await _send(request);
    final data = _decodeMap(response);
    if ((response.statusCode == 200 || response.statusCode == 201) && data != null) {
      return Attachment.fromJson(data);
    }
    throw ApiException(
        response.statusCode,
        _decodeError(response, 'Upload failed (${response.statusCode})'));
  }

  /// Default chunk size (4 MiB) used for large-file uploads.
  static const int chunkSizeBytes = 4 * 1024 * 1024;

  /// Threshold above which a file is uploaded in chunks instead of a single
  /// multipart request, so large files support resuming after interruptions.
  static const int chunkedUploadThreshold = 16 * 1024 * 1024;

  /// Uploads a file, transparently switching to chunked upload + resume for
  /// large files. [onProgress] reports a fraction in [0, 1] when provided.
  Future<Attachment> uploadAttachmentSmart(
    String filePath,
    String accessToken, {
    String visibility = 'public',
    ValueChanged<double>? onProgress,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    if (size < chunkedUploadThreshold) {
      onProgress?.call(1);
      return uploadAttachment(filePath, accessToken, visibility: visibility);
    }
    return _uploadAttachmentChunked(file, size, accessToken, visibility: visibility, onProgress: onProgress);
  }

  Future<Attachment> _uploadAttachmentChunked(
    File file,
    int fileSize,
    String accessToken, {
    required String visibility,
    ValueChanged<double>? onProgress,
  }) async {
    final totalChunks = (fileSize / chunkSizeBytes).ceil();
    final mimeType = _mediaTypeFor(file.path);

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
    try {
      for (var index = 1; index <= totalChunks; index++) {
        if (uploaded.contains(index)) {
          onProgress?.call(index / totalChunks);
          continue;
        }
        final start = (index - 1) * chunkSizeBytes;
        await raf.setPosition(start);
        final length = (start + chunkSizeBytes > fileSize)
            ? fileSize - start
            : chunkSizeBytes;
        final chunk = await raf.read(length);

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/attachments/chunk/$uploadId/$index'),
        );
        request.headers['Authorization'] = 'Bearer $accessToken';
        request.files.add(http.MultipartFile.fromBytes('chunk', chunk));
        final response = await _send(request);
        if (response.statusCode != 200) {
          throw ApiException(response.statusCode, _decodeError(response, 'Chunk upload failed'));
        }
        onProgress?.call(index / totalChunks);
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

  // ---- Posts ----

  Future<List<Post>> getPosts({int page = 1, int limit = 20, String? token, String? query}) async {
    final uri = query != null && query.trim().isNotEmpty
        ? Uri.parse('$baseUrl/posts?page=$page&limit=$limit&q=${Uri.encodeQueryComponent(query.trim())}')
        : Uri.parse('$baseUrl/posts?page=$page&limit=$limit');
    final response = await _get(uri, headers: _headers(token: token, json: false));
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
      {List<int> attachmentIds = const [], String visibility = 'public'}) async {
    final response = await _post(
      Uri.parse('$baseUrl/posts'),
      headers: _headers(token: accessToken),
      body: jsonEncode({
        'content': content,
        'attachment_ids': attachmentIds,
        'visibility': visibility,
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

  Future<ChatMessage> sendChatMessage(
    String accessToken,
    int conversationId,
    String content, {
    int? replyToId,
    List<int> attachmentIds = const [],
    List<int> mentions = const [],
  }) async {
    final body = <String, dynamic>{
      'content': content,
      'reply_to_id': replyToId,
      'attachment_ids': attachmentIds,
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
}
