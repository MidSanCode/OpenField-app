import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/consent_request.dart';
import '../models/conversation.dart';
import '../models/post.dart';
import '../models/post_reply.dart';
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

  String _decodeError(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
    } catch (_) {}
    return fallback;
  }

  // ---- Auth ----

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
    throw Exception(_decodeError(response, 'Login failed'));
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
    throw Exception(_decodeError(response, 'Registration failed'));
  }

  // ---- Account ----

  Future<User> getCurrentUser(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users/me'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) return User.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to get user'));
  }

  Future<User> getUser(String accessToken, int userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users/$userId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) return User.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to get user'));
  }

  Future<List<User>> searchUsers(String accessToken, String query, {int limit = 20}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users/search?q=${Uri.encodeQueryComponent(query)}&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['users'] as List?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((u) => User.fromJson(u))
          .toList();
    }
    throw Exception(_decodeError(response, 'Failed to search users'));
  }

  /// Returns the current user's effective permission keys and group names.
  Future<Map<String, dynamic>> getMyPermissions(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/users/me/permissions'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_decodeError(response, 'Failed to get permissions'));
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
    throw Exception(_decodeError(response, 'Failed to update profile'));
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

  Future<Attachment> uploadAttachment(String filePath, String accessToken) async {
    final data = await _uploadMultipart('$baseUrl/attachments', filePath, accessToken);
    return Attachment.fromJson(data);
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
    throw Exception(_decodeError(response, 'Failed to load attachments'));
  }

  Future<void> deleteAttachment(int attachmentId, String accessToken) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/attachments/$attachmentId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) throw Exception(_decodeError(response, 'Failed to delete attachment'));
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
    throw Exception(_decodeError(response, 'Upload failed (${response.statusCode})'));
  }

  // ---- Posts ----

  Future<List<Post>> getPosts({int page = 1, int limit = 20, String? token}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/posts?page=$page&limit=$limit'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final postsList = (data['posts'] as List?) ?? const [];
      return postsList.map((p) => Post.fromJson(p)).toList();
    }
    throw Exception(_decodeError(response, 'Failed to load posts'));
  }

  Future<Post> getPost(int postId, String token) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) return Post.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to load post'));
  }

  Future<Post> createPost(String content, String accessToken, {List<int> attachmentIds = const []}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/posts'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'attachment_ids': attachmentIds}),
    );
    if (response.statusCode == 201) return Post.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to create post'));
  }

  Future<Post> updatePost(int postId, String content, String accessToken, {List<int> attachmentIds = const []}) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'attachment_ids': attachmentIds}),
    );
    if (response.statusCode == 200) return Post.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to update post'));
  }

  Future<void> deletePost(int postId, String accessToken) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) throw Exception(_decodeError(response, 'Failed to delete post'));
  }

  // ---- Post replies ----

  Future<List<PostReply>> listReplies(int postId, String token, {int page = 1, int limit = 50}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/posts/$postId/replies?page=$page&limit=$limit'),
      headers: _headers(token: token, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['replies'] as List?) ?? const [];
      return list.whereType<Map<String, dynamic>>().map((r) => PostReply.fromJson(r)).toList();
    }
    throw Exception(_decodeError(response, 'Failed to load replies'));
  }

  Future<PostReply> createReply(int postId, String content, String accessToken, {int? parentId}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/posts/$postId/replies'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'parent_id': parentId}),
    );
    if (response.statusCode == 201) return PostReply.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to create reply'));
  }

  Future<PostReply> updateReply(int postId, int replyId, String content, String accessToken) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/posts/$postId/replies/$replyId'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content}),
    );
    if (response.statusCode == 200) return PostReply.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to update reply'));
  }

  Future<void> deleteReply(int postId, int replyId, String accessToken) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/posts/$postId/replies/$replyId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) throw Exception(_decodeError(response, 'Failed to delete reply'));
  }

  // ---- Chat: consent requests ----

  Future<List<ConsentRequest>> listConsentRequests(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/consent-requests'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['requests'] as List?) ?? const [];
      return list.whereType<Map<String, dynamic>>().map((r) => ConsentRequest.fromJson(r)).toList();
    }
    throw Exception(_decodeError(response, 'Failed to load requests'));
  }

  Future<Conversation?> acceptConsentRequest(String accessToken, int requestId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/consent-requests/$requestId/accept'),
      headers: _headers(token: accessToken),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final conv = data['conversation'];
      if (conv is Map<String, dynamic>) return Conversation.fromJson(conv);
      return null;
    }
    throw Exception(_decodeError(response, 'Failed to accept request'));
  }

  Future<void> declineConsentRequest(String accessToken, int requestId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/consent-requests/$requestId/decline'),
      headers: _headers(token: accessToken),
    );
    if (response.statusCode != 204) {
      throw Exception(_decodeError(response, 'Failed to decline request'));
    }
  }

  // ---- Chat: conversations ----

  Future<List<Conversation>> listConversations(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/conversations'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['conversations'] as List?) ?? const [];
      return list.whereType<Map<String, dynamic>>().map((c) => Conversation.fromJson(c)).toList();
    }
    throw Exception(_decodeError(response, 'Failed to load conversations'));
  }

  Future<ConversationDetail> getConversation(String accessToken, int conversationId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/conversations/$conversationId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      return ConversationDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_decodeError(response, 'Failed to load conversation'));
  }

  Future<Conversation> createGroup(String accessToken, String title) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/conversations'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'title': title}),
    );
    if (response.statusCode == 201) return Conversation.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to create group'));
  }

  Future<void> startPrivateChat(String accessToken, int userId, {String message = ''}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/conversations/start'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'user_id': userId, 'message': message}),
    );
    if (response.statusCode != 201) {
      throw Exception(_decodeError(response, 'Failed to start chat'));
    }
  }

  Future<void> inviteToGroup(String accessToken, int conversationId, int userId, {String message = ''}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/conversations/$conversationId/invite'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'user_id': userId, 'message': message}),
    );
    if (response.statusCode != 201) {
      throw Exception(_decodeError(response, 'Failed to send invite'));
    }
  }

  Future<void> updateNote(String accessToken, int conversationId, String note) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/conversations/$conversationId/note'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'note': note}),
    );
    if (response.statusCode != 200) throw Exception(_decodeError(response, 'Failed to update note'));
  }

  Future<void> updateGroupNickname(String accessToken, int conversationId, String nickname) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/conversations/$conversationId/group-nickname'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'group_nickname': nickname}),
    );
    if (response.statusCode != 200) {
      throw Exception(_decodeError(response, 'Failed to update group nickname'));
    }
  }

  Future<void> markConversationRead(String accessToken, int conversationId, int lastMessageId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/conversations/$conversationId/read'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'last_message_id': lastMessageId}),
    );
    if (response.statusCode != 204) {
      throw Exception(_decodeError(response, 'Failed to mark as read'));
    }
  }

  Future<void> leaveGroup(String accessToken, int conversationId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/conversations/$conversationId/leave'),
      headers: _headers(token: accessToken),
    );
    if (response.statusCode != 204) throw Exception(_decodeError(response, 'Failed to leave group'));
  }

  Future<void> removeGroupMember(String accessToken, int conversationId, int userId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/conversations/$conversationId/members/$userId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw Exception(_decodeError(response, 'Failed to remove member'));
    }
  }

  // ---- Chat: messages ----

  Future<List<ChatMessage>> listMessages(
    String accessToken,
    int conversationId, {
    int before = 0,
    int limit = 50,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/conversations/$conversationId/messages?before=$before&limit=$limit'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['messages'] as List?) ?? const [];
      return list.whereType<Map<String, dynamic>>().map((m) => ChatMessage.fromJson(m)).toList();
    }
    throw Exception(_decodeError(response, 'Failed to load messages'));
  }

  Future<ChatMessage> sendChatMessage(
    String accessToken,
    int conversationId,
    String content, {
    int? replyToId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/conversations/$conversationId/messages'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content, 'reply_to_id': replyToId}),
    );
    if (response.statusCode == 201) return ChatMessage.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to send message'));
  }

  Future<ChatMessage> editChatMessage(String accessToken, int conversationId, int messageId, String content) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId'),
      headers: _headers(token: accessToken),
      body: jsonEncode({'content': content}),
    );
    if (response.statusCode == 200) return ChatMessage.fromJson(jsonDecode(response.body));
    throw Exception(_decodeError(response, 'Failed to edit message'));
  }

  Future<void> deleteChatMessage(String accessToken, int conversationId, int messageId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId'),
      headers: _headers(token: accessToken, json: false),
    );
    if (response.statusCode != 204) {
      throw Exception(_decodeError(response, 'Failed to delete message'));
    }
  }
}
