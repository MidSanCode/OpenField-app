import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/services/chat_cache_store.dart';
import 'package:openfield/data/services/e2ee_service.dart';
import 'package:openfield/data/services/encrypted_chat_payload.dart';

/// On-disk cache for messages of MLS-encrypted conversations (IO platforms).
///
/// Unlike [ChatLocalDb] (a plaintext SQLite file), every message row in this
/// dedicated database keeps only the id / conversation / timestamp needed for
/// ordering and pagination in clear; everything sensitive — including the
/// decrypted plaintext, mentions and attachments — is sealed in an AES-256-GCM
/// `payload` blob under a key derived from the user's E2EE identity private
/// key. The file therefore cannot be read, merged into a backup or exfiltrated
/// without that key, and logging in as a different account (a different
/// identity) makes any leftover rows undecryptable.
class EncryptedChatDb implements ChatCacheStore {
  EncryptedChatDb._();

  static final EncryptedChatDb instance = EncryptedChatDb._();

  /// Dedicated encrypted caching is only available on mobile and desktop; the
  /// web target of this barrel uses IndexedDB instead.
  static bool get supported => !kIsWeb;

  Database? _db;
  Uint8List? _key;
  bool _ffiInitialized = false;

  Future<Database?> _open() async {
    if (!supported) return null;
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;

    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      if (!_ffiInitialized) {
        sqfliteFfiInit();
        _ffiInitialized = true;
      }
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'openfield_e2ee.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER NOT NULL,
            conversation_id INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            payload BLOB NOT NULL,
            PRIMARY KEY (conversation_id, id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_e2ee_conv_created ON messages (conversation_id, created_at)',
        );
      },
    );
    _db = db;
    return db;
  }

  /// The AES key that seals this store, derived from the E2EE identity. Null
  /// while no identity exists (fresh device / before first ensure).
  Future<Uint8List?> _keyOrNull() async {
    if (_key != null) return _key;
    final key = await E2eeService.instance.storageKey();
    if (key != null) _key = key;
    return key;
  }

  @override
  Future<int?> minMessageId(int conversationId) async {
    final db = await _open();
    if (db == null) return null;
    if (await _keyOrNull() == null) return null;
    final rows = await db.query(
      'messages',
      columns: ['MIN(id) AS min_id'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    if (rows.isEmpty) return null;
    final v = rows.first['min_id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  @override
  Future<List<ChatMessage>> loadMessages(
    int conversationId, {
    int? beforeId,
    int limit = 50,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    final key = await _keyOrNull();
    if (key == null) return const [];
    final where = <String>['conversation_id = ?'];
    final args = <Object?>[conversationId];
    if (beforeId != null) {
      where.add('id < ?');
      args.add(beforeId);
    }
    final rows = await db.query(
      'messages',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map((r) => _fromRow(r, key)).toList();
  }

  @override
  Future<List<ChatMessage>> loadMessagesFrom(
    int conversationId,
    int afterId, {
    int limit = 200,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    final key = await _keyOrNull();
    if (key == null) return const [];
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ? AND id > ?',
      whereArgs: [conversationId, afterId],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map((r) => _fromRow(r, key)).toList();
  }

  @override
  Future<void> replaceConversation(
      int conversationId, List<ChatMessage> messages) async {
    final db = await _open();
    if (db == null) return;
    if (await _keyOrNull() == null) return;
    await db.transaction((txn) async {
      await txn.delete(
          'messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
      for (final m in messages) {
        await _insert(txn, m, conversationId);
      }
    });
  }

  @override
  Future<void> appendMessages(
      int conversationId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _open();
    if (db == null) return;
    if (await _keyOrNull() == null) return;
    await db.transaction((txn) async {
      for (final m in messages) {
        await _insert(txn, m, conversationId, ignore: true);
      }
    });
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    final db = await _open();
    if (db == null) return;
    if (await _keyOrNull() == null) return;
    await _insert(db, message, message.conversationId, ignore: true);
  }

  @override
  Future<void> deleteMessage(int conversationId, int messageId) async {
    final db = await _open();
    if (db == null) return;
    await db.delete('messages',
        where: 'conversation_id = ? AND id = ?', whereArgs: [conversationId, messageId]);
  }

  @override
  Future<void> deleteConversation(int conversationId) async {
    final db = await _open();
    if (db == null) return;
    await db.delete(
        'messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
  }

  Future<void> _insert(
    DatabaseExecutor txn,
    ChatMessage m,
    int conversationId, {
    bool ignore = false,
  }) async {
    final key = await _keyOrNull();
    if (key == null) return;
    final payload = sealMessagePayload(m, key);
    if (payload == null) return;
    final sql = ignore
        ? 'INSERT OR IGNORE INTO messages (id, conversation_id, created_at, payload) VALUES (?,?,?,?)'
        : 'INSERT INTO messages (id, conversation_id, created_at, payload) VALUES (?,?,?,?)';
    await txn.rawInsert(sql, [
      m.id,
      conversationId,
      m.createdAt.toIso8601String(),
      payload,
    ]);
  }

  ChatMessage _fromRow(Map<String, Object?> r, Uint8List key) {
    final id = r['id'] as int;
    final conversationId = r['conversation_id'] as int;
    final createdAt = DateTime.parse(r['created_at'] as String);
    return openMessagePayload(r['payload'], key, id, conversationId, createdAt);
  }
}
