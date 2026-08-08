import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/models/chat_message.dart';

/// Local SQLite store for chat messages. It caches messages per conversation so
/// the UI can render instantly (offline-first) and only talk to the server for
/// messages the cache does not yet have.
class ChatLocalDb {
  ChatLocalDb._();

  static final ChatLocalDb instance = ChatLocalDb._();

  Database? _db;
  bool _ffiInitialized = false;

  /// Local SQLite caching is only available on mobile and desktop. On web the
  /// methods become no-ops so callers can share one code path.
  static bool get supported => !kIsWeb;

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
    final path = p.join(dir.path, 'openfield_chat.db');
    final db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER NOT NULL,
            conversation_id INTEGER NOT NULL,
            sender_id INTEGER NOT NULL,
            content TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'text',
            reply_to_id INTEGER,
            edited_at TEXT,
            deleted_at TEXT,
            created_at TEXT NOT NULL,
            sender_name TEXT,
            sender_avatar TEXT,
            sender_verified INTEGER NOT NULL DEFAULT 0,
            client_id TEXT,
            status INTEGER NOT NULL DEFAULT 2,
            PRIMARY KEY (conversation_id, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE message_attachments (
            message_id INTEGER NOT NULL,
            conversation_id INTEGER NOT NULL,
            attachment_id INTEGER NOT NULL,
            data TEXT NOT NULL,
            PRIMARY KEY (conversation_id, message_id, attachment_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_conv_created ON messages (conversation_id, created_at)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN client_id TEXT');
          await db.execute(
              'ALTER TABLE messages ADD COLUMN status INTEGER NOT NULL DEFAULT 2');
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE messages ADD COLUMN kind TEXT NOT NULL DEFAULT 'text'");
        }
      },
    );
    _db = db;
    return db;
  }

  /// Returns the lowest cached message id for a conversation, or null.
  Future<int?> minMessageId(int conversationId) async {
    final db = await _open();
    if (db == null) return null;
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

  /// Loads cached messages for a conversation, oldest first. When [beforeId]
  /// is provided, returns messages strictly older than it (for lazy loading).
  Future<List<ChatMessage>> loadMessages(
    int conversationId, {
    int? beforeId,
    int limit = 50,
  }) async {
    final db = await _open();
    if (db == null) return const [];
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
    final msgs = rows.reversed.map((r) => _fromRow(r)).toList();
    await _attach(db, msgs, conversationId);
    return msgs;
  }

  /// Loads cached messages newer than a given message id (used to seed the
  /// newest window after a server sync).
  Future<List<ChatMessage>> loadMessagesFrom(
    int conversationId,
    int afterId, {
    int limit = 200,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ? AND id > ?',
      whereArgs: [conversationId, afterId],
      orderBy: 'id ASC',
      limit: limit,
    );
    final msgs = rows.map((r) => _fromRow(r)).toList();
    await _attach(db, msgs, conversationId);
    return msgs;
  }

  /// Replaces the cached window for a conversation with [messages]. Used after
  /// a successful server fetch to keep the cache consistent.
  Future<void> replaceConversation(int conversationId, List<ChatMessage> messages) async {
    final db = await _open();
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
      await txn.delete(
          'message_attachments', where: 'conversation_id = ?', whereArgs: [conversationId]);
      for (final m in messages) {
        await _insert(txn, m, conversationId);
      }
    });
  }

  /// Appends messages to the cache, ignoring duplicates.
  Future<void> appendMessages(int conversationId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _open();
    if (db == null) return;
    await db.transaction((txn) async {
      for (final m in messages) {
        await _insert(txn, m, conversationId, ignore: true);
      }
    });
  }

  Future<void> upsertMessage(ChatMessage message) async {
    final db = await _open();
    if (db == null) return;
    await _insert(db, message, message.conversationId, ignore: true);
  }

  Future<void> deleteMessage(int conversationId, int messageId) async {
    final db = await _open();
    if (db == null) return;
    await db.delete('messages',
        where: 'conversation_id = ? AND id = ?', whereArgs: [conversationId, messageId]);
    await db.delete('message_attachments',
        where: 'conversation_id = ? AND message_id = ?', whereArgs: [conversationId, messageId]);
  }

  /// Removes all cached messages for a conversation (used after deletion).
  Future<void> deleteConversation(int conversationId) async {
    final db = await _open();
    if (db == null) return;
    await db.delete('messages', where: 'conversation_id = ?', whereArgs: [conversationId]);
    await db.delete('message_attachments',
        where: 'conversation_id = ?', whereArgs: [conversationId]);
  }

  Future<void> _insert(
    DatabaseExecutor txn,
    ChatMessage m,
    int conversationId, {
    bool ignore = false,
  }) async {
    final insert = ignore
        ? 'INSERT OR IGNORE INTO messages (id, conversation_id, sender_id, content, kind, reply_to_id, edited_at, deleted_at, created_at, sender_name, sender_avatar, sender_verified, client_id, status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)'
        : 'INSERT INTO messages (id, conversation_id, sender_id, content, kind, reply_to_id, edited_at, deleted_at, created_at, sender_name, sender_avatar, sender_verified, client_id, status) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
    await txn.rawInsert(insert, [
      m.id,
      conversationId,
      m.senderId,
      m.content,
      m.kind,
      m.replyToId,
      m.editedAt?.toIso8601String(),
      m.deletedAt?.toIso8601String(),
      m.createdAt.toIso8601String(),
      m.senderName,
      m.senderAvatar,
      m.senderVerified ? 1 : 0,
      m.clientId,
      m.status.index,
    ]);
    if (ignore) {
      await txn.delete('message_attachments',
          where: 'conversation_id = ? AND message_id = ?', whereArgs: [conversationId, m.id]);
    }
    for (final a in m.attachments) {
      await txn.rawInsert(
        'INSERT OR REPLACE INTO message_attachments (message_id, conversation_id, attachment_id, data) VALUES (?,?,?,?)',
        [m.id, conversationId, a.id, jsonEncode(a.toJson())],
      );
    }
  }

  Future<void> _attach(Database db, List<ChatMessage> msgs, int conversationId) async {
    if (msgs.isEmpty) return;
    final ids = msgs.map((m) => m.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'message_attachments',
      where: 'conversation_id = ? AND message_id IN ($placeholders)',
      whereArgs: [conversationId, ...ids],
    );
    final byMsg = <int, List<Attachment>>{};
    for (final r in rows) {
      final msgId = r['message_id'] as int;
      final raw = r['data'] as String;
      try {
        final map = jsonDecode(raw);
        if (map is Map<String, dynamic>) {
          byMsg.putIfAbsent(msgId, () => []).add(Attachment.fromJson(map));
        }
      } catch (_) {}
    }
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final atts = byMsg[m.id] ?? const <Attachment>[];
      msgs[i] = ChatMessage(
        id: m.id,
        conversationId: m.conversationId,
        senderId: m.senderId,
        content: m.content,
        kind: m.kind,
        replyToId: m.replyToId,
        editedAt: m.editedAt,
        deletedAt: m.deletedAt,
        createdAt: m.createdAt,
        senderName: m.senderName,
        senderAvatar: m.senderAvatar,
        senderVerified: m.senderVerified,
        clientId: m.clientId,
        status: m.status,
        attachments: atts,
      );
    }
  }

  DateTime? _parseTime(Object? v) {
    if (v is String && v.isNotEmpty) {
      return DateTime.tryParse(v);
    }
    return null;
  }

  ChatMessage _fromRow(Map<String, Object?> r) {
    final statusRaw = r['status'] as int? ?? 2;
    final status = MessageStatus.values.length > statusRaw
        ? MessageStatus.values[statusRaw]
        : MessageStatus.sent;
    return ChatMessage(
      id: r['id'] as int,
      conversationId: r['conversation_id'] as int,
      senderId: r['sender_id'] as int,
      content: r['content'] as String? ?? '',
      kind: r['kind'] as String? ?? 'text',
      replyToId: r['reply_to_id'] as int?,
      editedAt: _parseTime(r['edited_at']),
      deletedAt: _parseTime(r['deleted_at']),
      createdAt: DateTime.parse(r['created_at'] as String),
      senderName: r['sender_name'] as String?,
      senderAvatar: r['sender_avatar'] as String?,
      senderVerified: (r['sender_verified'] as int? ?? 0) != 0,
      clientId: r['client_id'] as String?,
      status: status,
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
