import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';

class AuthService extends ChangeNotifier {
  static const _keyAccessToken = 'access_token';
  static const _keyUsername = 'username';
  static const _keyEmail = 'email';
  static const _keyAvatarUrl = 'avatar_url';

  final ApiService _api = ApiService();

  String? _accessToken;
  String? _username;
  String? _email;
  String? _avatarUrl;
  User? _user;
  bool _isLoading = true;

  bool get isAuthenticated => _accessToken != null;
  bool get isLoading => _isLoading;
  String? get accessToken => _accessToken;
  String? get username => _username;
  String? get email => _email;
  String? get avatarUrl => _avatarUrl;
  User? get user => _user;

  AuthService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_keyAccessToken);
    _username = prefs.getString(_keyUsername);
    _email = prefs.getString(_keyEmail);
    _avatarUrl = prefs.getString(_keyAvatarUrl);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setTokens(String accessToken) async {
    _accessToken = accessToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    notifyListeners();
  }

  Future<void> setUser({String? username, String? email, String? avatarUrl}) async {
    if (username != null) _username = username;
    if (email != null) _email = email;
    if (avatarUrl != null) _avatarUrl = avatarUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, _username ?? '');
    await prefs.setString(_keyEmail, _email ?? '');
    await prefs.setString(_keyAvatarUrl, _avatarUrl ?? '');
    notifyListeners();
  }

  Future<void> setUsername(String username) => setUser(username: username);

  Future<void> setEmail(String email) => setUser(email: email);

  Future<void> setAvatarUrl(String avatarUrl) => setUser(avatarUrl: avatarUrl);

  /// Logs in with username + password (local accounts created by admins).
  Future<User> login(String username, String password) async {
    final result = await _api.login(username, password);
    final token = result['access_token'];
    if (token is! String || token.isEmpty) {
      throw Exception('Invalid login response');
    }
    await setTokens(token);
    final userData = result['user'];
    if (userData is Map<String, dynamic>) {
      final user = User.fromJson(userData);
      _user = user;
      await setUser(
        username: user.username,
        email: user.email,
        avatarUrl: user.avatarUrl,
      );
      return user;
    }
    return _user!;
  }

  /// Logs in with a pre-issued access token (e.g. copied from the browser's
  /// OIDC login result page when deep-link login is unavailable).
  Future<User> loginWithToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) throw Exception('Invalid token');
    final user = await _api.getCurrentUser(trimmed);
    await setTokens(trimmed);
    _user = user;
    await setUser(username: user.username, email: user.email, avatarUrl: user.avatarUrl);
    return user;
  }

  /// Completes registration for a new OAuth user.
  Future<User> register(String username, String nickname, {String bio = ''}) async {
    if (_accessToken == null) throw Exception('Not authenticated');
    final user = await _api.register(username, nickname, _accessToken!, bio: bio);
    _user = user;
    await setUser(username: user.username, email: user.email, avatarUrl: user.avatarUrl);
    return user;
  }

  /// Refreshes the current user profile from the server.
  Future<User?> fetchCurrentUser() async {
    if (_accessToken == null) return null;
    try {
      final user = await _api.getCurrentUser(_accessToken!);
      _user = user;
      await setUser(username: user.username, email: user.email, avatarUrl: user.avatarUrl);
      return user;
    } catch (e) {
      return null;
    }
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _username = null;
    _email = null;
    _avatarUrl = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyAvatarUrl);
    notifyListeners();
  }
}
