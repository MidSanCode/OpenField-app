import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:openfield/plugins/plugin_fs.dart';

/// dart:io-backed plugin filesystem for native platforms.
class PluginFileSystemImpl implements PluginFileSystem {
  @override
  Future<String> rootDir() async {
    final support = await getApplicationSupportDirectory();
    final dir =
        Directory('${support.path}${Platform.pathSeparator}plugins');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

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

  @override
  void writeBytes(String path, List<int> bytes) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  @override
  void writeText(String path, String text) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  @override
  void deleteRecursive(String path) {
    final d = Directory(path);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}

PluginFileSystem getPluginFileSystem() => PluginFileSystemImpl();
