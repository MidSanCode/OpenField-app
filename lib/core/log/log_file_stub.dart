import 'package:openfield/core/log/log_entry.dart';

/// No-op stub used on platforms without dart:io.
abstract class LogFileWriter {
  /// Discards the line; nothing is persisted.
  void write(String line);

  /// Completes immediately; nothing to close.
  Future<void> close();
}

/// Web/no-io variant; returns a writer that discards all lines.
LogFileWriter createLogFileWriter() => _StubLogFileWriter();

class _StubLogFileWriter implements LogFileWriter {
  @override
  void write(String line) {}

  @override
  Future<void> close() async {}
}

/// Metadata stub mirroring the IO variant; fields are always empty/zero.
class LogFileInfo {
  /// Always empty on this platform.
  final String path;
  /// Always empty on this platform.
  final String name;
  /// Always 0 on this platform.
  final int size;
  /// Zero time on this platform (no real file metadata exists).
  final DateTime modified;

  const LogFileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  /// Always empty on this platform.
  String get formattedSize => '';

  /// Always empty on this platform.
  String get formattedDate => '';
}

/// Always returns an empty list on this platform.
Future<List<LogFileInfo>> getLogFiles() async => [];

/// Always returns an empty list on this platform.
Future<List<LogEntry>> readLogFile(String path) async => [];
