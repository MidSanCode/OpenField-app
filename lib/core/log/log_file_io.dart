import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:openfield/core/log/log_entry.dart';

const int _kMaxLogFileSize = 5 * 1024 * 1024;
const int _kMaxLogFiles = 3;

/// Writes log lines to a rotating file in the application support directory.
abstract class LogFileWriter {
  /// Appends one already-formatted line (newline added by the writer).
  /// Calls before initialization are buffered in memory.
  void write(String line);
  /// Flushes and closes the underlying sink; safe when never written to.
  Future<void> close();
}

/// Creates the platform file writer (IO build; see [log_file_stub.dart] for
/// the web/no-io variant).
LogFileWriter createLogFileWriter() => _FileLogWriter._();

class _FileLogWriter implements LogFileWriter {
  IOSink? _sink;
  File? _currentFile;
  int _currentSize = 0;
  bool _initDone = false;
  final List<String> _pendingWrites = [];

  _FileLogWriter._();

  Future<void> _ensureOpen() async {
    if (_initDone) return;
    _initDone = true;

    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final files =
        (await logDir.list().toList())
            .whereType<File>()
            .where((f) => f.path.endsWith('.log'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFile = File('${logDir.path}/$timestamp.log');

    _sink = _currentFile!.openWrite(mode: FileMode.append);

    for (final f in files.skip(_kMaxLogFiles - 1)) {
      await f.delete();
    }

    for (final line in _pendingWrites) {
      _sink!.add('$line\n'.codeUnits);
      _currentSize += line.length + 1;
    }
    _pendingWrites.clear();
  }

  @override
  void write(String line) {
    if (_sink == null) {
      _pendingWrites.add(line);
      _ensureOpen();
      return;
    }
    _sink!.add('$line\n'.codeUnits);
    _currentSize += line.length + 1;
    if (_currentSize >= _kMaxLogFileSize) {
      _rotate();
    }
  }

  void _rotate() {
    _sink?.flush().then((_) {
      _sink?.close();
      _sink = null;
      _currentFile = null;
      _currentSize = 0;
    });
  }

  @override
  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

/// Metadata for one persisted log file, shown in the log viewer list.
class LogFileInfo {
  /// Absolute path of the .log file on disk.
  final String path;
  /// Bare file name (timestamp-based, e.g. `1730000000000.log`).
  final String name;
  /// File size in bytes.
  final int size;
  /// Last-modified time reported by the filesystem.
  final DateTime modified;

  const LogFileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  /// Human-readable size, rounded to one decimal in KB/MB.
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// `yyyy-MM-dd HH:mm` rendering of [modified].
  String get formattedDate {
    final d = modified;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// Lists the persisted .log files, newest first. Returns an empty list when
/// the log directory does not exist yet.
Future<List<LogFileInfo>> getLogFiles() async {
  final dir = await getApplicationSupportDirectory();
  final logDir = Directory('${dir.path}/logs');
  if (!await logDir.exists()) return [];

  final files =
      (await logDir.list().toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

  return files.map((f) {
    final stat = f.statSync();
    final name = f.path.split(Platform.pathSeparator).last;
    return LogFileInfo(
      path: f.path,
      name: name,
      size: stat.size,
      modified: stat.modified,
    );
  }).toList();
}

final Map<String, Level> _logLevelMap = {
  'all': Level.ALL,
  'finest': Level.FINEST,
  'finer': Level.FINER,
  'config': Level.CONFIG,
  'info': Level.INFO,
  'warning': Level.WARNING,
  'severe': Level.SEVERE,
  'shout': Level.SHOUT,
  'off': Level.OFF,
};

/// Parses a log file written by [LogFileWriter] back into [LogEntry]s, in
/// file order. Lines that fail to parse (or the ` | error:`/stack-trace
/// suffixes when malformed) are skipped rather than throwing; a missing file
/// yields an empty list.
Future<List<LogEntry>> readLogFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return [];

  final lines = await file.readAsLines();
  final entries = <LogEntry>[];

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    try {
      final match = RegExp(
        r'^\[(\d{4}-\d{2}-\d{2}T[\d:.]+)\] \[(\w+)\] (.+)$',
      ).firstMatch(line);
      if (match == null) continue;

      final timeStr = match.group(1)!;
      final levelStr = match.group(2)!.toLowerCase();
      final message = match.group(3)!;

      final parts = timeStr.split(RegExp(r'[T:.]'));
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final hour = int.parse(parts[3]);
      final minute = int.parse(parts[4]);
      final second = int.parse(parts[5]);
      final ms =
          int.tryParse(
            parts.length > 6 ? parts[6].padRight(3, '0').substring(0, 3) : '0',
          ) ??
          0;

      String? errorMsg;
      String? stackStr;
      final errorIdx = message.indexOf(' | error:');
      if (errorIdx != -1) {
        final rest = message.substring(errorIdx + 10);
        final stackIdx = rest.indexOf('\n');
        if (stackIdx != -1) {
          errorMsg = rest.substring(0, stackIdx);
          stackStr = rest.substring(stackIdx + 1);
        } else {
          errorMsg = rest;
        }
      }

      entries.add(
        LogEntry(
          timestamp: DateTime(year, month, day, hour, minute, second, ms),
          level: _logLevelMap[levelStr] ?? Level.INFO,
          message: errorIdx != -1 ? message.substring(0, errorIdx) : message,
          error: errorMsg,
          stackTrace: stackStr != null ? StackTrace.fromString(stackStr) : null,
        ),
      );
    } catch (_) {
      continue;
    }
  }

  return entries;
}
