import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/plugins/plugin_engine.dart';
import 'package:openfield/plugins/plugin_manifest.dart';
import 'package:openfield/plugins/plugin_prefs_box.dart';

final _log = Logger('PluginEngine');

/// Real plugin engine for IO platforms: owns a QuickJS runtime, evaluates the
/// entry script and mediates every privileged call through the permission
/// gateway.
///
/// The JS side gets a single global `of` object. Every privileged method is
/// asynchronous (promise-based) and travels through one bridge channel where
/// this engine checks the grant before doing anything:
///
/// ```js
/// const me = await of.account.me();
/// await of.storage.set('counter', 1);
/// const res = await of.http.fetch('https://api.example.com/v1/thing');
/// ```
class PluginEngineImpl implements PluginEngine {
  PluginEngineImpl({required this.manifest, required this.pluginDir});

  @override
  final PluginManifest manifest;

  /// Absolute directory holding manifest.json + the entry script.
  @override
  final String pluginDir;

  /// Grants currently in effect (mirrors PluginManager's persisted set).
  @override
  Set<String> grants = {};

  /// Provides the signed-in auth service, or null when logged out. Injected
  /// at start so the engine has no Provider dependency.
  @override
  AuthService? Function()? authAccessor;

  /// Local toast sink for `of.ui.toast`.
  @override
  void Function(String message)? toastSink;

  JavascriptRuntime? _runtime;
  bool _started = false;

  @override
  bool get running => _started && _runtime != null;

  /// Storage namespace prefix, isolated per plugin id.
  String get _storageNamespace => 'plugin_${manifest.id}_';

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Creates the JS runtime, injects the `of` bridge and evaluates the entry
  /// script, then invokes `onLoad` when the plugin defines one.
  @override
  Future<void> start({
    required Future<bool> Function(String permId) permissionCheck,
  }) async {
    if (_started) return;
    await PluginPrefsBox.instance.ensureLoaded();
    final entryFile = File('$pluginDir/${manifest.entry}');
    if (!entryFile.existsSync()) {
      throw Exception('entry script missing: ${manifest.entry}');
    }
    final code = entryFile.readAsStringSync();

    final runtime = getJavascriptRuntime();
    _runtime = runtime;
    try {
      runtime.enableHandlePromises();
      _injectBridge(runtime);
      runtime.onMessage('of.bridge', (args) {
        _onBridgeRequest(args, permissionCheck);
      });
      runtime.onMessage('of.log', (args) {
        if (args is List && args.isNotEmpty) {
          _log.info('[plugin:${manifest.id}] ${args.join(' ')}');
        }
      });

      final result = await runtime.evaluateAsync(code);
      await runtime.handlePromise(result);
      _started = true;

      // Optional lifecycle hook.
      await evalExpression('typeof onLoad === "function" ? onLoad() : null;');
      _log.info('plugin started: ${manifest.id}@${manifest.version}');
    } catch (e) {
      _log.warning('plugin ${manifest.id} failed to start: $e');
      dispose();
      rethrow;
    }
  }

  /// Invokes `onUnload` (when defined) and tears the runtime down. Safe to
  /// call repeatedly 鈥?used by disable/uninstall and by the secure-boot
  /// offline shutdown path.
  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    final runtime = _runtime;
    _runtime = null;
    if (runtime != null) {
      try {
        final r = await runtime.evaluateAsync(
            'typeof onUnload === "function" ? onUnload() : null;');
        await runtime.handlePromise(r);
      } catch (_) {}
      try {
        runtime.dispose();
      } catch (_) {}
    }
    _log.info('plugin stopped: ${manifest.id}');
  }

  @override
  void dispose() {
    _started = false;
    try {
      _runtime?.dispose();
    } catch (_) {}
    _runtime = null;
  }

  // ------------------------------------------------------------------
  // Evaluation helpers
  // ------------------------------------------------------------------

  /// Evaluates an expression on the active runtime and drains pending jobs so
  /// promise continuations run.
  @override
  Future<dynamic> evalExpression(String expression) async {
    final runtime = _runtime;
    if (runtime == null || !_started) return null;
    final result = await runtime.evaluateAsync(expression);
    return runtime.handlePromise(result);
  }

  // ------------------------------------------------------------------
  // Bridge implementation
  // ------------------------------------------------------------------

  /// Injects the `of` global + the promise plumbing used by every bridged
  /// call. Pure JS, no permissions involved.
  void _injectBridge(JavascriptRuntime runtime) {
    runtime.evaluate(r'''
var __ofPending = {};
var __ofSeq = 0;
function __ofCall(op, payload) {
  return new Promise(function(resolve, reject) {
    var id = ++__ofSeq;
    __ofPending[id] = { resolve: resolve, reject: reject };
    sendMessage('of.bridge', JSON.stringify({ id: id, op: op, payload: payload === undefined ? null : payload }));
  });
}
function __ofDeliver(id, ok, valueJson) {
  var p = __ofPending[id];
  if (!p) return;
  delete __ofPending[id];
  if (ok) {
    try { p.resolve(JSON.parse(valueJson)); } catch (e) { p.resolve(valueJson); }
  } else {
    p.reject(new Error(valueJson));
  }
}
var of = {
  version: 1,
  log: function(msg) { try { sendMessage('of.log', JSON.stringify({ msg: String(msg) })); } catch (e) {} },
  storage: {
    get: function(key) { return __ofCall('storage.get', { key: String(key) }); },
    set: function(key, value) { return __ofCall('storage.set', { key: String(key), value: value }); },
    remove: function(key) { return __ofCall('storage.remove', { key: String(key) }); }
  },
  http: {
    fetch: function(url, options) { return __ofCall('http.fetch', { url: String(url||''), options: options || {} }); }
  },
  posts: {
    list: function(page) { return __ofCall('posts.list', { page: page || 1 }); }
  },
  chat: {
    conversations: function() { return __ofCall('chat.conversations', null); },
    send: function(conversationId, text) { return __ofCall('chat.send', { conversationId: conversationId, text: String(text||'') }); }
  },
  account: {
    me: function() { return __ofCall('account.me', null); }
  },
  ui: {
    toast: function(msg) { return __ofCall('ui.toast', { text: String(msg||'') }); }
  }
};
''');
  }

  /// Bridge entry: validate shape 鈫?check permission 鈫?execute 鈫?deliver.
  /// All failures are delivered back as rejected promises; nothing throws
  /// into the engine's dispatch loop.
  void _onBridgeRequest(dynamic args, Future<bool> Function(String) permCheck) {
    int? id;
    String op = '';
    dynamic payload;
    try {
      if (args is! Map) return;
      id = (args['id'] as num?)?.toInt();
      op = (args['op'] ?? '').toString();
      payload = args['payload'];
      if (id == null) return;
    } catch (_) {
      return;
    }

    () async {
      try {
        final result = await _execute(op, payload, permCheck);
        _deliver(id!, true, result);
      } catch (e) {
        _deliver(id!, false, e.toString());
      }
    }();
  }

  void _deliver(int id, bool ok, Object? value) {
    final runtime = _runtime;
    if (runtime == null || !_started) return;
    final encoded = jsonEncode(value.toString());
    try {
      runtime.evaluate('__ofDeliver($id, $ok, $encoded);');
      runtime.executePendingJob();
    } catch (e) {
      _log.warning('bridge deliver failed (${manifest.id}): $e');
    }
  }

  Future<Object?> _execute(
    String op,
    dynamic payload,
    Future<bool> Function(String permId) permCheck,
  ) async {
    switch (op) {
      case 'storage.get':
        return _withPermission('storage', permCheck, () async {
          final key = _requireString(payload, 'key');
          return {'value': PluginPrefsBox.instance.get('$_storageNamespace$key')};
        });
      case 'storage.set':
        return _withPermission('storage', permCheck, () async {
          final key = _requireString(payload, 'key');
          PluginPrefsBox.instance.set('$_storageNamespace$key', payload?['value']);
          return {'ok': true};
        });
      case 'storage.remove':
        return _withPermission('storage', permCheck, () async {
          final key = _requireString(payload, 'key');
          PluginPrefsBox.instance.remove('$_storageNamespace$key');
          return {'ok': true};
        });

      case 'http.fetch':
        return _withPermission('http.fetch', permCheck, () async {
          final url = _requireString(payload, 'url');
          return _httpFetch(url, payload?['options']);
        });

      case 'posts.list':
        return _withPermission('posts.read', permCheck, () async {
          final token = _authToken();
          final page = (payload?['page'] as num?)?.toInt() ?? 1;
          final posts =
              await ApiService().getPosts(page: page, limit: 20, token: token);
          return {
            'posts': posts
                .map((p) => {
                      'id': p.id,
                      'content': p.content.length > 500
                          ? p.content.substring(0, 500)
                          : p.content,
                      'author': p.authorName,
                      'createdAt': p.createdAt.toIso8601String(),
                    })
                .toList(),
          };
        });

      case 'chat.conversations':
        return _withPermission('chat.read', permCheck, () async {
          final list =
              await ApiService().listConversations(_authTokenRequired());
          return {
            'conversations': list
                .map((c) => {
                      'id': c.id,
                      'type': c.type,
                      'title': c.title,
                      'unread': c.unread,
                    })
                .toList(),
          };
        });

      case 'chat.send':
        return _withPermission('chat.send', permCheck, () async {
          final convId = (payload?['conversationId'] as num?)?.toInt();
          final text = _requireString(payload, 'text');
          if (convId == null) throw Exception('conversationId is required');
          final msg = await ApiService()
              .sendChatMessage(_authTokenRequired(), convId, text);
          return {'id': msg.id};
        });

      case 'account.me':
        return _withPermission('account.profile', permCheck, () async {
          final auth = authAccessor?.call();
          return {
            'username': auth?.username ?? '',
            'nickname': auth?.user?.nickname ?? auth?.username ?? '',
            'email': auth?.user?.email ?? '',
          };
        });

      case 'ui.toast':
        return _withPermission('ui.toast', permCheck, () async {
          toastSink?.call(_requireString(payload, 'text'));
          return {'ok': true};
        });

      default:
        throw Exception('unknown operation: $op');
    }
  }

  String? _authToken({bool required = false}) {
    final auth = authAccessor?.call();
    final token = auth?.accessToken;
    if (token == null && required) throw Exception('not signed in');
    return token;
  }

  String _authTokenRequired() => _authToken(required: true)!;

  static Future<Object?> _withPermission(
    String permId,
    Future<bool> Function(String permId) check,
    Future<Object?> Function() action,
  ) async {
    if (!await check(permId)) {
      throw Exception('permission denied: $permId');
    }
    return action();
  }

  String _requireString(dynamic payload, String field) {
    final v = payload is Map ? payload[field] : null;
    if (v is! String || v.isEmpty) {
      throw Exception('field "$field" must be a non-empty string');
    }
    return v;
  }

  /// Outbound HTTP limited to hosts declared in the manifest's allow-list.
  /// Even with the `http.fetch` permission granted, an undeclared host is
  /// refused 鈥?this keeps a malicious "weather widget" from quietly
  /// exfiltrating data anywhere it likes.
  Future<Map<String, dynamic>> _httpFetch(String url, dynamic options) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw Exception('invalid url');
    }
    final host = uri.host.toLowerCase();
    if (!manifest.allowedHosts.contains(host)) {
      throw Exception('host not allowed by manifest: $host');
    }
    final method =
        ((options is Map ? options['method'] : null) ?? 'GET').toString().toUpperCase();
    final headers = <String, String>{};
    final rawHeaders = options is Map ? options['headers'] : null;
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
    }
    final body = options is Map ? options['body'] : null;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, uri);
      headers.forEach(req.headers.set);
      if (body != null && method != 'GET' && method != 'HEAD') {
        req.add(utf8.encode(body.toString()));
      }
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final text =
          await utf8.decodeStream(resp.cast<List<int>>()).timeout(const Duration(seconds: 15));
      return {
        'status': resp.statusCode,
        'body': text.length > 256 * 1024 ? text.substring(0, 256 * 1024) : text,
      };
    } finally {
      client.close(force: true);
    }
  }
}

