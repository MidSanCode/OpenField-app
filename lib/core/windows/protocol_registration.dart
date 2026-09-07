import 'dart:io';

/// Registers the `openfield://` URL scheme under HKCU for this executable so
/// Windows launches the app on protocol links (e.g. OAuth callbacks).
/// Re-writes the registry keys only when the existing `shell\open\command`
/// does not already point at the running executable. A no-op on non-Windows
/// platforms; `reg` failures (missing tool, access denied) are swallowed.
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
  // The empty "URL Protocol" named value is what marks the key as a custom
  // URL scheme; without it Windows / browsers ignore the handler even when the
  // shell\open\command is correctly set. This was the reason the protocol was
  // not honoured after install on some machines.
  runReg(['add', key, '/v', 'URL Protocol', '/t', 'REG_SZ', '/d', '', '/f']);
  await setDefault(r'shell\open\command', quoted);
}
