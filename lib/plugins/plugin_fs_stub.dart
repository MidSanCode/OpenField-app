import 'package:openfield/plugins/plugin_fs.dart';

/// Web placeholder filesystem: plugins cannot be installed or executed in the
/// browser (no real filesystem, no QuickJS runtime), so every listing is
/// empty and every write throws a clear error.
class PluginFileSystemStub implements PluginFileSystem {
  /// Web stub: fixed virtual path; nothing is ever created.
  @override
  Future<String> rootDir() async => '/virtual/plugins';

  /// Web stub: always empty — no plugin can be installed in the browser.
  @override
  List<PluginFsEntry> listDirs(String dir) => const [];

  /// Web stub: always null — no bundle files exist in the browser.
  @override
  String? readText(String path) => null;

  /// Web stub: throws [UnsupportedError] instead of writing.
  @override
  void writeBytes(String path, List<int> bytes) {
    throw UnsupportedError('plugin installation requires a native platform');
  }

  /// Web stub: throws [UnsupportedError] instead of writing.
  @override
  void writeText(String path, String text) {
    throw UnsupportedError('plugin installation requires a native platform');
  }

  /// Web stub: no-op (there is nothing to delete).
  @override
  void deleteRecursive(String path) {}
}

/// Web-branch factory selected by plugin_fs.dart's conditional export;
/// returns the browser placeholder filesystem.
PluginFileSystem getPluginFileSystem() => PluginFileSystemStub();
