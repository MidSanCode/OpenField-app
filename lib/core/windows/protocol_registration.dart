import 'dart:io';

Future<void> ensureOpenFieldProtocol() async {
  if (!Platform.isWindows) return;

  final exePath = Platform.resolvedExecutable;
  final quoted = '"$exePath" "%1"';
  final key = r'HKCU\Software\Classes\openfield';

  String? runReg(List<String> args) {
    try {
      final result = Process.runSync('reg', args, runInShell: true);
      if (result.exitCode != 0) return null;
      return result.stdout.toString().trim();
    } on ProcessException catch (_) {
      return null;
    }
  }

  Future<String?> queryDefault(String subKey) async {
    final out = runReg(['query', '$key\\$subKey', '/ve']);
    if (out == null) return null;
    final match = RegExp(r'=\s*(.+)').firstMatch(out);
    return match?.group(1)?.trim();
  }

  Future<void> setDefault(String subKey, String value) async {
    final safe = value.replaceAll('"', '\\"');
    runReg(['add', '$key\\$subKey', '/ve', '/t', 'REG_SZ', '/d', safe, '/f']);
  }

  final existing = await queryDefault(r'shell\open\command');
  if (existing != null && existing.contains(exePath)) return;

  runReg(['add', key, '/f']);
  await setDefault('', 'URL:OpenField Protocol');
  await setDefault(r'shell\open\command', quoted);
}
