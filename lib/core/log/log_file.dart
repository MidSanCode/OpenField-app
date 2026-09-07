// Conditional export: uses the dart:io writer when available, the no-op
// stub (web) otherwise.
export 'log_file_stub.dart' if (dart.library.io) 'log_file_io.dart';
