/// One voice/video call as reported by the server.
///
/// The server owns the call state machine (`ringing` → `active` → `ended`) and
/// never sees media; the client uses this model to render the call UI and to
/// recover state after a missed push (see `CallService`).
class CallSession {
  /// Server-side call id, used for every signalling request.
  final int id;

  /// Conversation the call belongs to (always a one-to-one chat today).
  final int conversationId;

  /// User who placed the call.
  final int initiatorId;

  /// `audio` or `video`.
  final String mode;

  /// `ringing`, `active` or `ended`.
  final String state;

  /// Why the call ended (`hung_up`, `cancelled`, `declined`, `timeout`);
  /// empty while the call is live.
  final String endReason;

  /// Connect time in seconds, as derived by the server; 0 until answered.
  final int durationSeconds;

  /// When the call was placed; null when the server omitted it.
  final DateTime? createdAt;

  /// Creates a call record.
  const CallSession({
    required this.id,
    required this.conversationId,
    required this.initiatorId,
    required this.mode,
    required this.state,
    required this.endReason,
    required this.durationSeconds,
    this.createdAt,
  });

  /// True while the callee has not answered yet.
  bool get isRinging => state == 'ringing';

  /// True once the callee accepted.
  bool get isActive => state == 'active';

  /// True once the call is over.
  bool get isEnded => state == 'ended';

  /// True when this call carries video.
  bool get isVideo => mode == 'video';

  /// Parses a call payload, tolerating missing fields and string-typed ids.
  factory CallSession.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value.toString());
      } catch (_) {
        return null;
      }
    }

    return CallSession(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversation_id']),
      initiatorId: _asInt(json['initiator_id']),
      mode: json['mode']?.toString() ?? 'audio',
      state: json['state']?.toString() ?? 'ringing',
      endReason: json['end_reason']?.toString() ?? '',
      durationSeconds: _asInt(json['duration_seconds']),
      createdAt: parseDate(json['created_at']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
