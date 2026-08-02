import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
class RealtimeService {
  static final RealtimeService instance = RealtimeService();

  final _controller = StreamController<PushEvent>.broadcast();

  WebSocket? _socket;
  bool _shouldRun = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  int _retryCount = 0;
  String? _token;

  /// Stream of incoming push events. Listen once; the connection stays alive
  /// for the lifetime of the service.
  Stream<PushEvent> get events => _controller.stream;

  /// True when a live WebSocket connection is established.
  bool get isConnected => _socket != null;

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
    _closeSocket();
  }

  void _open() {
    if (!_shouldRun || _disposed || _token == null) return;
    final socket = _socket;
    if (socket != null && (socket.readyState == WebSocket.open)) {
      return;
    }
    _closeSocket();
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
      final wsUri = _wsUri();
      final socket = await WebSocket.connect(
        wsUri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!_shouldRun || _disposed) {
        socket.close();
        return;
      }
      _socket = socket;
      _retryCount = 0;
      _listen(socket);
    } catch (e) {
      debugPrint('[WS] connect failed: $e');
      _socket = null;
      if (_shouldRun && !_disposed) {
        _retryCount++;
        final delay = Duration(seconds: (2 * _retryCount).clamp(1, 30));
        _reconnectTimer = Timer(delay, () => _connectNow());
      }
    }
  }

  void _listen(WebSocket socket) {
    socket.listen(
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
        if (identical(_socket, socket)) {
          _socket = null;
        }
        if (_shouldRun && !_disposed) {
          _retryCount++;
          final delay = Duration(seconds: (2 * _retryCount).clamp(1, 30));
          _reconnectTimer = Timer(delay, () => _connectNow());
        }
      },
      onError: (Object e) {
        debugPrint('[WS] error: $e');
        if (identical(_socket, socket)) {
          _socket = null;
        }
      },
      cancelOnError: false,
    );
  }

  void _closeSocket() {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.close();
    }
  }

  static String _wsUri() {
    final base = ApiService.baseUrl;
    final host = base.replaceFirst('http://', '').replaceFirst('https://', '');
    final path = host.contains('/') ? host.substring(host.indexOf('/')) : '/';
    final authority = host.contains('/') ? host.substring(0, host.indexOf('/')) : host;
    final scheme = base.startsWith('https') ? 'wss' : 'ws';
    return '$scheme://$authority$path/ws';
  }
}
