import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:openfield/plugins/plugin_fs.dart';

/// dart:io-backed plugin filesystem for native platforms.
class PluginFileSystemImpl implements PluginFileSystem {
  /// Native implementation: `<app support>/plugins`, created on first call.
  @override
  Future<String> rootDir() async {
    final support = await getApplicationSupportDirectory();
    final dir =
        Directory('${support.path}${Platform.pathSeparator}plugins');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Native implementation: synchronous scan; a missing directory yields
  /// an empty list.
  @override
  List<PluginFsEntry> listDirs(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .whereType<Directory>()
        .map((e) => PluginFsEntry(e.path))
        .toList();
  }

  /// Native implementation: synchronous read; null when missing/unreadable.
  @override
  String? readText(String path) {
    final f = File(path);
    if (!f.existsSync()) return null;
    try {
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  /// Native implementation: creates parent directories, then writes bytes.
  @override
  void writeBytes(String path, List<int> bytes) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  /// Native implementation: creates parent directories, then writes UTF-8.
  @override
  void writeText(String path, String text) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  /// Native implementation: recursive delete; a missing path is a no-op.
  @override
  void deleteRecursive(String path) {
    final d = Directory(path);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}

/// IO-branch factory selected by plugin_fs.dart's conditional export;
/// returns the real dart:io-backed filesystem for native platforms.
PluginFileSystem getPluginFileSystem() => PluginFileSystemImpl();
