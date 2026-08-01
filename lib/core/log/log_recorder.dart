import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:openfield/core/log/log_entry.dart';
import 'package:openfield/core/log/log_file.dart';

const int kMaxLogs = 5000;

/// Collects [Logger] records into an in-memory ring buffer and writes them to
/// rotating log files when enabled. Exposed to the UI via [ChangeNotifier].
class LogService extends ChangeNotifier {
  LogService._();

  static final LogService instance = LogService._();

  StreamSubscription<LogRecord>? _subscription;
  LogFileWriter? _fileWriter;
  final List<LogEntry> _entries = [];
  bool _enabled = false;

  bool get enabled => _enabled;
  List<LogEntry> get entries => List.unmodifiable(_entries);
  LogFileWriter? get fileWriter => _fileWriter;

  /// Enables or disables logging. When disabled, buffered logs are cleared.
  void setEnabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      _start();
    } else {
      _stop();
    }
    notifyListeners();
  }

  void _start() {
    _subscription?.cancel();
    _entries.clear();
    _fileWriter = createLogFileWriter();
    _subscription = Logger.root.onRecord.listen((record) {
      final entry = LogEntry(
        timestamp: record.time,
        level: record.level,
        message: record.message,
        error: record.error,
        stackTrace: record.stackTrace,
      );
      _fileWriter?.write(entry.toFileLine());
      _entries.add(entry);
      if (_entries.length > kMaxLogs) {
        _entries.removeRange(0, _entries.length - kMaxLogs);
      }
      notifyListeners();
    });
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _fileWriter?.close();
    _fileWriter = null;
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
