import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/realtime_service.dart';
/// Secure-boot style availability gate for the plugin system.
///
/// Plugins only ever execute inside a *verified online session*: at startup —
/// and again after every connectivity change — the gate probes a public,
/// cheap endpoint (`GET /api/v1/capabilities`). While the probe fails, every
/// plugin runtime is torn down and stays disabled, so sideloaded code can
/// never run in an unverified environment (e.g. DNS hijack, captive portal)
/// or while the device is offline.
enum PluginGateState {
  /// Initial state: probing, plugins not started yet.
  probing,

  /// Server reachable — enabled plugins may boot.
  online,

  /// Server unreachable — all plugin runtimes must be stopped.
  offline,
}

class PluginGate extends ChangeNotifier {
  PluginGate._();

  static final PluginGate instance = PluginGate._();

  PluginGateState _state = PluginGateState.probing;
  DateTime? _lastProbeAt;
  Timer? _retryTimer;
  bool _disposed = false;

  /// Previous connected flag of [RealtimeService]; used to detect
  /// connected → dropped transitions, which immediately disable plugins.
  bool? _wasRealtimeConnected;

  PluginGateState get state => _state;

  /// True when plugin runtimes are allowed to run.
  bool get allowsPlugins => _state == PluginGateState.online;

  DateTime? get lastProbeAt => _lastProbeAt;

  static const _probeTimeout = Duration(seconds: 5);
  static const _retryInterval = Duration(seconds: 15);

  /// Starts probing and keeps watching connectivity for the app's lifetime.
  void start() {
    // The realtime service notifies on connect/disconnect; a socket drop is
    // treated as an immediate offline signal (conservative: plugins stop
    // first, verification follows later).
    RealtimeService.instance.addListener(_onRealtimeChanged);
    probe();
  }

  void _onRealtimeChanged() {
    final connected = RealtimeService.instance.isConnected;
    final was = _wasRealtimeConnected;
    _wasRealtimeConnected = connected;
    if (_disposed) return;
    if (was == true && !connected) {
      markOffline();
    } else if (connected) {
      probe();
    }
  }

  /// Probes the server once and transitions [state] accordingly.
  Future<void> probe() async {
    _retryTimer?.cancel();
    final ok = await _ping();
    if (_disposed) return;
    _lastProbeAt = DateTime.now();
    final next = ok ? PluginGateState.online : PluginGateState.offline;
    _state = next;
    if (!ok) {
      _retryTimer = Timer(_retryInterval, probe);
    }
    notifyListeners();
  }

  /// Forces the offline state without waiting for a probe to fail.
  void markOffline() {
    _retryTimer?.cancel();
    if (_disposed || _state == PluginGateState.offline) return;
    _state = PluginGateState.offline;
    notifyListeners();
  }

  Future<bool> _ping() async {
    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(
              Uri.parse('${ApiService.baseUrl}/capabilities'),
              headers: {'Accept': 'application/json'},
            )
            .timeout(_probeTimeout);
        return resp.statusCode >= 200 && resp.statusCode < 500;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    RealtimeService.instance.removeListener(_onRealtimeChanged);
    super.dispose();
  }
}
