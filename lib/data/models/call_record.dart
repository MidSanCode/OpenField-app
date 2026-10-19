/// Structured payload of a call history entry (message kind `call`).
///
/// The server stores no sentence for a call: it stores this record, and each
/// client phrases it from its own translations. That is what lets the same row
/// read as "Missed call" for the callee and "No answer" for the caller.
class CallRecord {
  /// Creates a call record.
  const CallRecord({
    required this.callId,
    required this.mode,
    required this.outcome,
    required this.durationSeconds,
    required this.initiatorId,
  });

  /// Server-side call session id.
  final int callId;

  /// `audio` or `video`.
  final String mode;

  /// One of [outcomeAnswered], [outcomeDeclined], [outcomeMissed],
  /// [outcomeCancelled].
  final String outcome;

  /// Talk time in seconds; 0 unless the call was answered.
  final int durationSeconds;

  /// User id that placed the call.
  final int initiatorId;

  /// Outcome for a call the callee picked up.
  static const String outcomeAnswered = 'answered';

  /// Outcome for a call the callee rejected.
  static const String outcomeDeclined = 'declined';

  /// Outcome for a call that rang out unanswered.
  static const String outcomeMissed = 'missed';

  /// Outcome for a call the caller abandoned before an answer.
  static const String outcomeCancelled = 'cancelled';

  /// Whether this was a video call.
  bool get isVideo => mode == 'video';

  /// True when the call connected and has a talk time to show.
  bool get wasAnswered => outcome == outcomeAnswered;

  /// Parses the payload, returning null when it is absent or malformed so an
  /// unreadable record never breaks a message list.
  static CallRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    return CallRecord(
      callId: _asInt(map['call_id']),
      mode: map['mode']?.toString() ?? 'audio',
      outcome: map['outcome']?.toString() ?? outcomeMissed,
      durationSeconds: _asInt(map['duration_seconds']),
      initiatorId: _asInt(map['initiator_id']),
    );
  }

  /// Renders [seconds] as `mm:ss`, folding hours into minutes the way a phone
  /// dialler does.
  static String formatDuration(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final minutes = total ~/ 60;
    final rest = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
