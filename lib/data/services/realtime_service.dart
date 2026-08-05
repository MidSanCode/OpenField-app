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
/// a broadcast stream of [PushEvent]s. Automatically reconnects with backoff.
///
/// Uses [WebSocketChannel] from `web_socket_channel`, which works on both
/// native and web. Browsers cannot set custom headers on WebSocket connections,
/// so the access token is passed as a `token` query parameter instead; the
/// gateway validates it before forwarding the upgrade.
class RealtimeService {
  static final RealtimeService instance = RealtimeService();

  final _controller = StreamController<PushEvent>.broadcast();

  WebSocketChannel? _channel;
  bool _shouldRun = false;
  bool _disposed = false;
  bool _connected = false;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  String? _token;

  /// Stream of incoming push events. Listen once; the connection stays alive
  /// for the lifetime of the service.
  Stream<PushEvent> get events => _controller.stream;

  /// True when a live WebSocket connection is established.
  bool get isConnected => _connected;

  /// Connects (or reconnects) to the push service using the current token.
  void connect(String token) {
    _shouldRun = true;
    _disposed = false;
    _token = token;
    _open();
  }

  /// Disconnects and stops all reconnection attempts.
  void disconnect() {
    _shouldRun = false;
    _disposed = true;
    _token = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
  }

  void _open() {
    if (!_shouldRun || _disposed || _token == null) return;
    if (_connected) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    // Small delay so the UI settles before opening the socket.
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 1), () {
      _connectNow();
    });
  }

  Future<void> _connectNow() async {
    if (!_shouldRun || _disposed) return;
    final token = _token;
    if (token == null) return;
    try {
      final wsUri = _wsUri(token);
      final channel = WebSocketChannel.connect(wsUri);
      await channel.ready;
      if (!_shouldRun || _disposed) {
        channel.sink.close();
        return;
      }
      _channel = channel;
      _connected = true;
      _retryCount = 0;
      _listen(channel);
    } catch (e) {
      debugPrint('[WS] connect failed: $e');
      _channel = null;
      _connected = false;
      if (_shouldRun && !_disposed) {
        _retryCount++;
        final delay = Duration(seconds: (2 * _retryCount).clamp(1, 30));
        _reconnectTimer = Timer(delay, () => _connectNow());
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
          _retryCount++;
          final delay = Duration(seconds: (2 * _retryCount).clamp(1, 30));
          _reconnectTimer = Timer(delay, () => _connectNow());
        }
      },
      onError: (Object e) {
        debugPrint('[WS] error: $e');
        if (identical(_channel, channel)) {
          _channel = null;
        }
        _connected = false;
      },
      cancelOnError: false,
    );
  }

  void _closeChannel() {
    final channel = _channel;
    _channel = null;
    _connected = false;
    if (channel != null) {
      channel.sink.close();
    }
  }

  static Uri _wsUri(String token) {
    final base = ApiService.baseUrl;
    final host = base.replaceFirst('http://', '').replaceFirst('https://', '');
    final path = host.contains('/') ? host.substring(host.indexOf('/')) : '/';
    final authority = host.contains('/') ? host.substring(0, host.indexOf('/')) : host;
    final scheme = base.startsWith('https') ? 'wss' : 'ws';
    return Uri.parse('$scheme://$authority$path/ws?token=$token');
  }
}
