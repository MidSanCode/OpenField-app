import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:openfield/data/services/api_service.dart';

/// A single push event delivered over the realtime WebSocket connection.
class PushEvent {
  final String type;
  final int? conversationId;
  final int? messageId;
  final int? postId;
  final int? replyId;
  final int? userId;
  final Map<String, dynamic> data;

  PushEvent({
    required this.type,
    this.conversationId,
    this.messageId,
    this.postId,
    this.replyId,
    this.userId,
    required this.data,
  });

  factory PushEvent.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map<String, dynamic>?) ?? {};
    return PushEvent(
      type: (json['type'] as String?) ?? '',
      conversationId: _asInt(data['conversation_id']),
      messageId: _asInt(data['id'] ?? data['message_id']),
      postId: _asInt(data['post_id'] ?? data['id']),
      replyId: _asInt(data['id'] ?? data['reply_id']),
      userId: _asInt(data['user_id']),
      data: data,
    );
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is num) return v.toInt();
    return null;
  }
}

/// Maintains a persistent WebSocket connection to the push service and exposes
/// a broadcast stream of [PushEvent]s.
///
/// Reconnect policy: on a connection failure (or the socket closing), retry
/// every 5 seconds up to [maxConsecutiveFailures] consecutive failures, then
/// give up and flip to a "dead" state that the UI surfaces with a banner and a
/// manual "reconnect" button. Any successful connection resets the counter, so
/// a stable link is never torn down by the failure budget.
///
/// Uses [WebSocketChannel] from `web_socket_channel`, which works on both
/// native and web. Browsers cannot set custom headers on WebSocket upgrade
/// requests, so the client never puts its long-lived JWT in the URL (it would
/// leak into proxy/access logs): it first POSTs `/ws` with the Bearer token to
/// mint a single-use ticket, then connects with `?ticket=` within the TTL.
class RealtimeService extends ChangeNotifier {
  static final RealtimeService instance = RealtimeService();

  /// Consecutive failures tolerated before the connection is declared dead.
  static const int maxConsecutiveFailures = 3;

  /// Delay between reconnection attempts.
  static const Duration retryInterval = Duration(seconds: 5);

  final _controller = StreamController<PushEvent>.broadcast();

  WebSocketChannel? _channel;
  bool _shouldRun = false;
  bool _disposed = false;
  bool _connected = false;
  bool _dead = false;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  String? _token;

  /// Stream of incoming push events. Listen once; the connection stays alive
  /// for the lifetime of the service.
  Stream<PushEvent> get events => _controller.stream;

  /// True when a live WebSocket connection is established.
  bool get isConnected => _connected;

  /// True after [maxConsecutiveFailures] consecutive failed attempts. The UI
  /// shows a banner offering a manual retry via [reconnect].
  bool get isDead => _dead;

  /// Number of consecutive failed attempts so far (resets on success).
  int get retryCount => _retryCount;

  /// Connects (or reconnects) to the push service using the current token.
  void connect(String token) {
    _shouldRun = true;
    _disposed = false;
    _dead = false;
    _retryCount = 0;
    _token = token;
    notifyListeners();
    _open();
  }

  /// Manually retries a dead connection. Resets the failure counter so the new
  /// attempt gets the full budget again.
  void reconnect() {
    if (!_shouldRun || _disposed || _token == null) return;
    _dead = false;
    _retryCount = 0;
    notifyListeners();
    _open();
  }

  /// Disconnects and stops all reconnection attempts.
  void disconnect() {
    _shouldRun = false;
    _disposed = true;
    _token = null;
    _dead = false;
    _retryCount = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
    notifyListeners();
  }

  void _open() {
    if (!_shouldRun || _disposed || _token == null) return;
    if (_connected) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    // Small delay so the UI settles before opening the socket.
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 600), () {
      _connectNow();
    });
  }

  Future<void> _connectNow() async {
    if (!_shouldRun || _disposed) return;
    final token = _token;
    if (token == null) return;
    try {
      // Exchange the long-lived JWT for a short-lived single-use ticket; the
      // ticket (not the token) travels in the upgrade URL.
      final ticketData = await ApiService().createWsTicket(token);
      final ticket = ticketData['ticket'];
      if (ticket is! String || ticket.isEmpty) {
        throw ApiException(null, 'Empty connection ticket');
      }
      if (!_shouldRun || _disposed) return;
      final wsUri = _wsUri(ticket);
      final channel = WebSocketChannel.connect(wsUri);
      await channel.ready;
      if (!_shouldRun || _disposed) {
        channel.sink.close();
        return;
      }
      _channel = channel;
      _connected = true;
      _retryCount = 0;
      _dead = false;
      notifyListeners();
      _listen(channel);
    } catch (e) {
      debugPrint('[WS] connect failed: $e');
      _channel = null;
      _connected = false;
      if (_shouldRun && !_disposed) {
        _registerFailure();
      }
    }
  }

  void _listen(WebSocketChannel channel) {
    channel.stream.listen(
      (message) {
        if (message is String) {
          try {
            final decoded = jsonDecode(message);
            if (decoded is Map<String, dynamic>) {
              _controller.add(PushEvent.fromJson(decoded));
            }
          } catch (e) {
            debugPrint('[WS] bad message: $e');
          }
        }
      },
      onDone: () {
        if (identical(_channel, channel)) {
          _channel = null;
        }
        _connected = false;
        if (_shouldRun && !_disposed) {
          _registerFailure();
        }
      },
      onError: (Object e) {
        debugPrint('[WS] error: $e');
        if (identical(_channel, channel)) {
          _channel = null;
        }
        _connected = false;
        if (_shouldRun && !_disposed) {
          _registerFailure();
        }
      },
      cancelOnError: false,
    );
  }

  /// Counts a failed attempt; after [maxConsecutiveFailures] the connection is
  /// declared dead and reconnection stops until the user taps retry.
  /// A retry already scheduled from a related callback (e.g. the same socket
  /// firing both onError and onDone) is not counted twice.
  void _registerFailure() {
    if (_reconnectTimer != null) return;
    _retryCount++;
    if (_retryCount >= maxConsecutiveFailures) {
      _dead = true;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      debugPrint('[WS] giving up after $_retryCount consecutive failures');
      notifyListeners();
      return;
    }
    _reconnectTimer = Timer(retryInterval, () => _connectNow());
  }

  void _closeChannel() {
    final channel = _channel;
    _channel = null;
    _connected = false;
    if (channel != null) {
      channel.sink.close();
    }
  }

  static Uri _wsUri(String ticket) {
    final base = ApiService.baseUrl;
    final host = base.replaceFirst('http://', '').replaceFirst('https://', '');
    final path = host.contains('/') ? host.substring(host.indexOf('/')) : '/';
    final authority = host.contains('/') ? host.substring(0, host.indexOf('/')) : host;
    final scheme = base.startsWith('https') ? 'wss' : 'ws';
    final query = Uri(queryParameters: {'ticket': ticket}).query;
    return Uri.parse('$scheme://$authority$path/ws?$query');
  }
}
