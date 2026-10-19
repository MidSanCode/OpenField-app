/// ICE configuration handed out by the server for WebRTC calls.
///
/// The server owns the relay settings so an operator configures TURN once in the
/// server config instead of every user filling in a settings field.
class CallIceConfig {
  /// Creates the configuration.
  const CallIceConfig({required this.servers, required this.turnConfigured});

  /// Entries in the shape WebRTC expects, e.g.
  /// `{'urls': 'stun:host:19302'}` or
  /// `{'urls': 'turn:host:3478', 'username': 'u', 'credential': 'c'}`.
  final List<Map<String, dynamic>> servers;

  /// Whether the deployment configured a TURN relay.
  ///
  /// False means calls can only connect when neither peer sits behind a
  /// symmetric NAT: STUN discovers addresses, it cannot relay media.
  final bool turnConfigured;

  /// Parses the `GET /calls/ice` payload.
  static CallIceConfig fromJson(Map<String, dynamic> json) {
    final servers = <Map<String, dynamic>>[];
    final raw = json['ice_servers'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          servers.add(Map<String, dynamic>.from(entry));
        }
      }
    }
    return CallIceConfig(
      servers: servers,
      turnConfigured: json['turn'] == true,
    );
  }
}
