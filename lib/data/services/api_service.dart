import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/attachment.dart';
import '../models/post.dart';
import '../models/user.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080/api/v1';
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers({String? token, bool json = true}) {
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (json) headers['Content-Type'] = 'application/json';
    return headers;
  }

  Future<String> getOIDCLoginUrl() async {
    final response = await _client.get(Uri.parse('$baseUrl/auth/oidc/login'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['auth_url'] as String;
    }
    throw Exception('Failed to get OIDC login URL');
  }

  Future<Map<String, dynamic>> oidcCallback(String code) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/auth/oidc/callback?code=$code'),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('OIDC callback failed');
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers(),
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Login failed');
  }

  Future<User> register(String username, String nickname, String accessToken) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'username': username, 'nickname': nickname}),
    );
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    if (response.statusCode == 409) throw Exception('Username already taken');
    throw Exception('Registration failed');
  }

  Future<List<Post>> getPosts({int page = 1, int limit = 20}) async {
    final response = await _client.get(Uri.parse('$baseUrl/posts?page=$page&limit=$limit'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final postsList = (data['posts'] as List?) ?? const [];
      return postsList.map((p) => Post.fromJson(p)).toList();
    }
    throw Exception('Failed to load posts');
  }

  Future<Post> createPost(String content, String accessToken, {List<int> attachmentIds = const []}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/posts'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'attachment_ids': attachmentIds}),
    );
    if (response.statusCode == 201) return Post.fromJson(jsonDecode(response.body));
    throw Exception('Failed to create post');
  }

  Future<Post> updatePost(int postId, String content, String accessToken, {List<int> attachmentIds = const []}) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'attachment_ids': attachmentIds}),
    );
    if (response.statusCode == 200) return Post.fromJson(jsonDecode(response.body));
    throw Exception('Failed to update post');
  }

  Future<void> deletePost(int postId, String accessToken) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) throw Exception('Failed to delete post');
  }

  Future<User> getCurrentUser(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) return User.fromJson(jsonDecode(response.body));
    throw Exception('Failed to get user');
  }

  Future<User> updateProfile(String accessToken, {String? username, String? nickname}) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (nickname != null) body['nickname'] = nickname;
    final response = await _client.put(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers(token: accessToken),
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) return User.fromJson(jsonDecode(response.body));
    throw Exception('Failed to update profile');
  }

  Future<Attachment> uploadAttachment(String filePath, String accessToken) async {
    final data = await _uploadMultipart('$baseUrl/attachments', filePath, accessToken);
    return Attachment.fromJson(data);
  }

  Future<User> uploadAvatar(String filePath, String accessToken) async {
    final att = await _uploadMultipart('$baseUrl/users/me/avatar', filePath, accessToken);
    return User.fromJson(att);
  }

  Future<User> uploadBanner(String filePath, String accessToken) async {
    final att = await _uploadMultipart('$baseUrl/users/me/banner', filePath, accessToken);
    return User.fromJson(att);
  }

  Future<Map<String, dynamic>> _uploadMultipart(String url, String filePath, String accessToken) async {
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    String message = 'Upload failed (${response.statusCode})';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['error'] is String) message = body['error'] as String;
    } catch (_) {}
    throw Exception(message);
  }

  Future<List<Attachment>> listMyAttachments(String accessToken, {int limit = 100}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/attachments?limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['attachments'] as List?) ?? const [];
      return list.whereType<Map<String, dynamic>>().map((a) => Attachment.fromJson(a)).toList();
    }
    throw Exception('Failed to load attachments');
  }

  Future<void> deleteAttachment(int attachmentId, String accessToken) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/attachments/$attachmentId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) throw Exception('Failed to delete attachment');
  }

  Future<List<dynamic>> getMessages(int otherUserId, String accessToken, {int limit = 50}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/messages/$otherUserId?limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final messages = (data['messages'] as List?) ?? const [];
      return messages;
    }
    throw Exception('Failed to load messages');
  }

  Future<Map<String, dynamic>> sendMessage(int receiverId, String content, String accessToken) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/messages'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'receiver_id': receiverId, 'content': content}),
    );
    if (response.statusCode == 201) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Failed to send message');
  }
}

