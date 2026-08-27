import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/secure_kv.dart';

class AuthService extends ChangeNotifier {
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyAccessExpiresAt = 'access_expires_at';
  static const _keyUsername = 'username';
  static const _keyEmail = 'email';
  static const _keyAvatarUrl = 'avatar_url';
  static const _keyBoundHost = 'bound_host';

  // Fields persisted per server host under 'session.<host>.<field>'. Tokens
  // and expiry live in secure storage; profile metadata stays in prefs.
  static const _sessionTokenFields = [
    'access_token',
    'refresh_token',
    'access_expires_at',
  ];
  static const _sessionProfileFields = ['username', 'email', 'avatar_url'];

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

  /// The server host the current session was issued by. Sessions are bound to
  /// their server so the account can be restored when the host changes.
  String? _boundHost;

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

  /// Completes once persisted session state has been read. [switchServer]
  /// awaits this before touching the session to avoid racing startup.
  late final Future<void> _loadFuture;

  AuthService() {
    _loadFuture = _load();
  }

  Future<void> _load() async {
    // Move legacy plaintext tokens from SharedPreferences into the platform
    // credential store before reading anything.
    await SecureKV.migrate();
    final prefs = await SharedPreferences.getInstance();
    _boundHost = prefs.getString(_keyBoundHost);
    _accessToken = await SecureKV.read(_keyAccessToken);
    _refreshToken = await SecureKV.read(_keyRefreshToken);
    final expRaw = await SecureKV.read(_keyAccessExpiresAt);
    final expMs = expRaw != null ? int.tryParse(expRaw) : null;
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
        if (!await refreshAccessToken()) {
          return;
        }
      }
      // Always load the full profile on startup so the user id is available
      // immediately (chat bubble alignment, author attribution, avatar, ...)
      // even after a page refresh. Also validates the session and starts the
      // auto-refresh loop.
      await _verifySession();
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
    // Bind the session to the server that issued it so it can be restored when
    // the user switches back to this server host.
    _boundHost = ApiService.serverHost;
    await prefs.setString(_keyBoundHost, _boundHost!);
    await SecureKV.write(_keyAccessToken, accessToken);
    if (_refreshToken != null) {
      await SecureKV.write(_keyRefreshToken, _refreshToken!);
    }
    await SecureKV.write(
        _keyAccessExpiresAt, _accessExpiresAt!.millisecondsSinceEpoch.toString());
    _startRefreshLoop();
    startHeartbeat();
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
    stopHeartbeat();
    _accessToken = null;
    _refreshToken = null;
    _accessExpiresAt = null;
    _username = null;
    _email = null;
    _avatarUrl = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyAvatarUrl);
    await SecureKV.delete(_keyAccessToken);
    await SecureKV.delete(_keyRefreshToken);
    await SecureKV.delete(_keyAccessExpiresAt);
    // Forgetting the session also forgets the account saved for this server,
    // so switching back does not silently restore a logged-out account.
    await _removeSessionForHost(prefs, _boundHost);
    notifyListeners();
  }

  /// Switches the active account to the one saved for [newHost]. The current
  /// session is persisted under the host that issued it, then, if an account
  /// was previously saved for [newHost], that session is restored and
  /// re-validated against the new server; otherwise the user is logged out so
  /// they can sign in on the new server.
  Future<void> switchServer(String newHost) async {
    await _loadFuture;
    newHost = _normalizeHost(newHost);
    if (newHost == _boundHost) return;

    await _saveSessionForHost(_boundHost);
    _boundHost = newHost;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBoundHost, newHost);

    final saved = await _loadSessionForHost(newHost);
    if (saved?.accessToken != null) {
      await _applySession(saved!);
      _user = null;
      _startRefreshLoop();
      notifyListeners();
      if (isAccessTokenExpired) {
        if (!await refreshAccessToken()) {
          await clearTokens();
          return;
        }
      }
      await _verifySession();
    } else {
      await clearTokens();
    }
  }

  Future<void> _applySession(_SavedSession s) async {
    _accessToken = s.accessToken;
    _refreshToken = s.refreshToken;
    _accessExpiresAt = s.accessExpiresAt;
    _username = s.username;
    _email = s.email;
    _avatarUrl = s.avatarUrl;
    if (s.accessToken != null) {
      await SecureKV.write(_keyAccessToken, s.accessToken!);
    }
    await SecureKV.write(_keyRefreshToken, s.refreshToken ?? '');
    await SecureKV.write(_keyAccessExpiresAt,
        (s.accessExpiresAt?.millisecondsSinceEpoch ?? 0).toString());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, s.username ?? '');
    await prefs.setString(_keyEmail, s.email ?? '');
    await prefs.setString(_keyAvatarUrl, s.avatarUrl ?? '');
  }

  /// Persists the active session under [host] so it can be restored later.
  /// With no active session, any stale copy for [host] is removed instead.
  Future<void> _saveSessionForHost(String? host) async {
    if (host == null || host.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken == null) {
      await _removeSessionForHost(prefs, host);
      return;
    }
    for (final field in _sessionTokenFields) {
      final value = _sessionTokenField(field);
      if (value != null) {
        await SecureKV.write(_sessionKey(host, field), value);
      } else {
        await SecureKV.delete(_sessionKey(host, field));
      }
    }
    await prefs.setString(_sessionKey(host, 'username'), _username ?? '');
    await prefs.setString(_sessionKey(host, 'email'), _email ?? '');
    await prefs.setString(_sessionKey(host, 'avatar_url'), _avatarUrl ?? '');
  }

  String? _sessionTokenField(String field) {
    switch (field) {
      case 'access_token':
        return _accessToken;
      case 'refresh_token':
        return _refreshToken;
      case 'access_expires_at':
        return _accessExpiresAt?.millisecondsSinceEpoch.toString();
    }
    return null;
  }

  Future<void> _removeSessionForHost(SharedPreferences prefs, String? host) async {
    if (host == null || host.isEmpty) return;
    for (final field in _sessionTokenFields) {
      await SecureKV.delete(_sessionKey(host, field));
    }
    for (final field in _sessionProfileFields) {
      await prefs.remove(_sessionKey(host, field));
    }
  }

  Future<_SavedSession?> _loadSessionForHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    final access = await SecureKV.read(_sessionKey(host, 'access_token'));
    if (access == null || access.isEmpty) return null;
    final expRaw = await SecureKV.read(_sessionKey(host, 'access_expires_at'));
    final expMs = expRaw != null ? int.tryParse(expRaw) : null;
    return _SavedSession(
      accessToken: access,
      refreshToken: await SecureKV.read(_sessionKey(host, 'refresh_token')),
      accessExpiresAt:
          expMs != null ? DateTime.fromMillisecondsSinceEpoch(expMs) : null,
      username: prefs.getString(_sessionKey(host, 'username')),
      email: prefs.getString(_sessionKey(host, 'email')),
      avatarUrl: prefs.getString(_sessionKey(host, 'avatar_url')),
    );
  }

  String _sessionKey(String host, String field) => 'session.$host.$field';

  String _normalizeHost(String host) =>
      host.trim().replaceAll(RegExp(r'/+$'), '');

  @override
  void dispose() {
    _stopRefreshLoop();
    super.dispose();
  }


  // --- heartbeat presence loop ---

  Timer? _heartbeatTimer;

  /// Starts a 60-second heartbeat loop that tells the server the user is
  /// still around so friends can see them as online. The loop is cancelled
  /// when the user signs out so anonymous traffic is never billed to the
  /// currently-authenticated user id.
  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    final String? token = _accessToken;
    if (token == null) return;
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      try {
        await _api.sendHeartbeat(token);
      } catch (_) {
        // Heartbeats are best-effort; network blips recover on the next tick.
      }
    });
  }

  /// Stops the presence heartbeat (called on sign-out).
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}

/// A persisted account session saved for a specific server host.
class _SavedSession {
  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessExpiresAt;
  final String? username;
  final String? email;
  final String? avatarUrl;

  _SavedSession({
    this.accessToken,
    this.refreshToken,
    this.accessExpiresAt,
    this.username,
    this.email,
    this.avatarUrl,
  });
}
