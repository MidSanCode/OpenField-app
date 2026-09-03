import 'package:openfield/plugins/plugin_fs.dart';

/// Web placeholder filesystem: plugins cannot be installed or executed in the
/// browser (no real filesystem, no QuickJS runtime), so every listing is
/// empty and every write throws a clear error.
class PluginFileSystemStub implements PluginFileSystem {
  @override
  Future<String> rootDir() async => '/virtual/plugins';

  @override
  List<PluginFsEntry> listDirs(String dir) => const [];

  @override
  String? readText(String path) => null;

  @override
  void writeBytes(String path, List<int> bytes) {
    throw UnsupportedError('plugin installation requires a native platform');
  }

  @override
  void writeText(String path, String text) {
    throw UnsupportedError('plugin installation requires a native platform');
  }

  @override
  void deleteRecursive(String path) {}
}

PluginFileSystem getPluginFileSystem() => PluginFileSystemStub();
