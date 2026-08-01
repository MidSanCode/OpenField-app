import 'package:logging/logging.dart';

/// A single recorded log entry.
class LogEntry {
  final DateTime timestamp;
  final Level level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  /// Formats the entry as a single persisted line.
  String toFileLine() {
    final buf = StringBuffer();
    buf.write('[${_formatTime(timestamp)}] [${level.name}] $message');
    if (error != null) {
      buf.write(' | error: $error');
    }
    if (stackTrace != null) {
      buf.write('\n$stackTrace');
    }
    return buf.toString();
  }

  String _formatTime(DateTime dt) {
    final y = dt.year.toString();
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-${d}T$h:$mi:$s.$ms';
  }
}
