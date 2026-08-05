import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';

class AuthService extends ChangeNotifier {
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyAccessExpiresAt = 'access_expires_at';
  static const _keyUsername = 'username';
  static const _keyEmail = 'email';
  static const _keyAvatarUrl = 'avatar_url';

  final ApiService _api = ApiService();

  String? _accessToken;
  String? _refreshToken;
  DateTime? _accessExpiresAt;
  String? _username;
  String? _email;
  String? _avatarUrl;
  User? _user;
  bool _isLoading = true;
  Timer? _refreshTimer;

  bool get isAuthenticated => _accessToken != null;
  bool get isLoading => _isLoading;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  DateTime? get accessExpiresAt => _accessExpiresAt;
  String? get username => _username;
  String? get email => _email;
  String? get avatarUrl => _avatarUrl;
  User? get user => _user;

  /// True when the stored access token has expired and can no longer be used.
  bool get isAccessTokenExpired =>
      _accessExpiresAt != null && _accessExpiresAt!.isBefore(DateTime.now());

  AuthService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_keyAccessToken);
    _refreshToken = prefs.getString(_keyRefreshToken);
    final expMs = prefs.getInt(_keyAccessExpiresAt);
    _accessExpiresAt =
        expMs != null ? DateTime.fromMillisecondsSinceEpoch(expMs) : null;
    _username = prefs.getString(_keyUsername);
    _email = prefs.getString(_keyEmail);
    _avatarUrl = prefs.getString(_keyAvatarUrl);
    _isLoading = false;
    notifyListeners();
    if (_accessToken != null) {
      if (isAccessTokenExpired) {
        // Session resumed with an already-expired access token: try to refresh
        // right away, clearing the session if that is no longer possible.
        await refreshAccessToken();
      } else if (_refreshToken == null) {
        // Legacy session saved before the refresh feature shipped: it has no
        // refresh token and no recorded expiry. Verify it against the server
        // and clear it if the token is no longer accepted.
        await _verifySession();
      } else {
        _startRefreshLoop();
      }
    }
  }

  /// Validates the stored access token against the server. Used for legacy
  /// sessions that have no refresh token to fall back on. Tolerates transient
  /// network errors, but clears the session when the server rejects the token.
  Future<void> _verifySession() async {
    final token = _accessToken;
    if (token == null) return;
    try {
      final user = await _api.getCurrentUser(token);
      _user = user;
      await setUser(username: user.username, email: user.email, avatarUrl: user.avatarUrl);
      _startRefreshLoop();
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await clearTokens();
      } else {
        _startRefreshLoop();
      }
    } catch (_) {
      _startRefreshLoop();
    }
  }

  /// Stores a session and starts the auto-refresh loop. [expiresIn] is the
  /// access token lifetime in seconds; [refreshExpiresIn] the refresh token
  /// lifetime (used to decide when a refresh is no longer possible).
  Future<void> setTokens(
    String accessToken, {
    String? refreshToken,
    int? expiresIn,
    int? refreshExpiresIn,
  }) async {
    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    _accessExpiresAt =
        DateTime.now().add(Duration(seconds: expiresIn ?? (24 * 60 * 60)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    if (_refreshToken != null) {
      await prefs.setString(_keyRefreshToken, _refreshToken!);
    }
    await prefs.setInt(_keyAccessExpiresAt, _accessExpiresAt!.millisecondsSinceEpoch);
    _startRefreshLoop();
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
    await setTokens(
      token,
      refreshToken: result['refresh_token'] as String?,
      expiresIn: (result['expires_in'] as num?)?.toInt(),
      refreshExpiresIn: (result['refresh_expires_in'] as num?)?.toInt(),
    );
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

  /// Logs in with a pre-issued token pair (e.g. copied from the browser's
  /// OIDC login result page when deep-link login is unavailable). Paste the
  /// access token and the refresh token (any whitespace/newline separated).
  /// Without a refresh token the session ends when the access token expires.
  Future<User> loginWithToken(String token) async {
    final parts = token
        .trim()
        .split(RegExp(r'[\s,;]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final access = parts.isNotEmpty ? parts.first : '';
    if (access.isEmpty) throw Exception('Invalid token');
    final refresh = parts.length > 1 ? parts[1] : null;
    final user = await _api.getCurrentUser(access);
    await setTokens(access, refreshToken: refresh);
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

  /// Exchanges the refresh token for a fresh access token. On success the new
  /// tokens are persisted and the auto-refresh loop is rescheduled. On failure
  /// (expired or revoked refresh token) the session is cleared and the user
  /// must log in again.
  Future<bool> refreshAccessToken() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final result = await _api.refreshAccessToken(refresh);
      final token = result['access_token'];
      if (token is! String || token.isEmpty) {
        await clearTokens();
        return false;
      }
      await setTokens(
        token,
        refreshToken: result['refresh_token'] as String?,
        expiresIn: (result['expires_in'] as num?)?.toInt(),
        refreshExpiresIn: (result['refresh_expires_in'] as num?)?.toInt(),
      );
      return true;
    } catch (_) {
      // Refresh token invalid/expired or server unreachable: force re-login.
      await clearTokens();
      return false;
    }
  }

  /// Kicks off a periodic timer that refreshes the access token shortly before
  /// it expires, keeping the session alive while the user is active. When the
  /// refresh fails the session is cleared (auto logout).
  void _startRefreshLoop() {
    _refreshTimer?.cancel();
    // Poll every minute and refresh when the access token is close to expiry.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final exp = _accessExpiresAt;
      if (exp == null) return;
      // Refresh when within 5 minutes of expiry (or already past it). If the
      // refresh is not possible or fails, the session is over: clear it so the
      // user can log in again instead of being stuck with a dead token.
      if (exp.difference(DateTime.now()) < const Duration(minutes: 5)) {
        if (!await refreshAccessToken()) {
          await clearTokens();
        }
      }
    });
  }

  void _stopRefreshLoop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> clearTokens() async {
    _stopRefreshLoop();
    _accessToken = null;
    _refreshToken = null;
    _accessExpiresAt = null;
    _username = null;
    _email = null;
    _avatarUrl = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyAccessExpiresAt);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyAvatarUrl);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopRefreshLoop();
    super.dispose();
  }
}
