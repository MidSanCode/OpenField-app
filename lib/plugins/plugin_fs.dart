/// Platform dispatch for the plugin filesystem layer.
///
/// The manager scans, extracts and deletes plugin bundles on a real
/// filesystem, which only exists on IO platforms. Web gets a stub whose
/// listings come back empty and whose writes fail with a clear error, so the
/// manager itself never imports dart:io and web builds stay clean.
library;

export 'plugin_fs_stub.dart' if (dart.library.io) 'plugin_fs_io.dart';

/// One plugin directory found under the plugins root.
class PluginFsEntry {
  /// Absolute (or virtual, on web) directory path.
  final String path;

  const PluginFsEntry(this.path);
}

/// Filesystem operations the plugin manager needs. Implemented with dart:io
/// on native platforms; see [getPluginFileSystem].
abstract class PluginFileSystem {
  /// The plugins root directory (created on demand).
  Future<String> rootDir();

  /// Lists the immediate subdirectories of [dir] (plugin install dirs).
  List<PluginFsEntry> listDirs(String dir);

  /// Reads a UTF-8 text file, or null when missing/unreadable.
  String? readText(String path);

  /// Writes raw bytes, creating the parent directory as needed.
  void writeBytes(String path, List<int> bytes);

  /// Writes UTF-8 text, creating the parent directory as needed.
  void writeText(String path, String text);

  /// Deletes a directory tree; missing directories are a no-op.
  void deleteRecursive(String path);
}
