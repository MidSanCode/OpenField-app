import 'dart:async';
import 'dart:convert';

import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/services/chat_cache_store.dart';
import 'package:openfield/data/services/idb_database.dart';

/// IndexedDB cache for chat messages of non-encrypted conversations (web).
/// Mirrors the SQLite schema of the IO target: one `messages` object store
/// keyed by [conversationId, id] plus a `message_attachments` store keyed by
/// [conversationId, messageId, attachmentId], so the UI code path is
/// identical across platforms and the offline-first render works in the
/// browser too.
class ChatLocalDb implements ChatCacheStore {
  ChatLocalDb._();

  static final ChatLocalDb instance = ChatLocalDb._();

  IdbDatabase? _db;

  /// The web build always supports the IndexedDB cache.
  static bool get supported => true;

  static const _messages = 'messages';
  static const _attachments = 'message_attachments';

  Future<IdbDatabase> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await IdbDatabase.open(
      name: 'openfield_chat',
      version: 1,
      onUpgradeNeeded: (txn, oldVersion, newVersion) {
        if (oldVersion < 1) {
          txn.objectStore(_messages, createIfMissing: true);
          txn.objectStore(_attachments, createIfMissing: true);
        }
      },
    );
    _db = db;
    return db;
  }

  @override
  Future<int?> minMessageId(int conversationId) async {
    final db = await _open();
    int? minId;
    await db.run(
      stores: [_messages],
      write: false,
      body: (txn) async {
        await txn.objectStore(_messages).openCursor(
              range: IdbKeys.conversation(conversationId),
              direction: 'next',
              onRow: (row) {
                minId = (row.value as Map)['id'] as int?;
                return false; // first key in ascending order = lowest id
              },
            );
      },
    );
    return minId;
  }

  @override
  Future<List<ChatMessage>> loadMessages(
    int conversationId, {
    int? beforeId,
    int limit = 50,
  }) async {
    final db = await _open();
    final rows = <Map>[];
    await db.run(
      stores: [_messages],
      write: false,
      body: (txn) async {
        await txn.objectStore(_messages).openCursor(
              range: beforeId != null
                  ? IdbKeys.conversationBefore(conversationId, beforeId)
                  : IdbKeys.conversation(conversationId),
              direction: 'prev', // newest first
              onRow: (row) {
                rows.add(row.value as Map);
                return rows.length < limit;
              },
            );
      },
    );
    final out = rows.reversed.toList(); // oldest first for the caller
    final ids = out.map((r) => r['id'] as int).toList();
    final atts = await _attachmentsFor(conversationId, ids);
    return out.map((r) => _fromRow(r, atts)).toList();
  }

  @override
  Future<List<ChatMessage>> loadMessagesFrom(
    int conversationId,
    int afterId, {
    int limit = 200,
  }) async {
    final db = await _open();
    final rows = <Map>[];
    await db.run(
      stores: [_messages],
      write: false,
      body: (txn) async {
        await txn.objectStore(_messages).openCursor(
              range: IdbKeys.conversationFromInclusive(
                  conversationId, afterId + 1),
              direction: 'next',
              onRow: (row) {
                rows.add(row.value as Map);
                return rows.length < limit;
              },
            );
      },
    );
    final ids = rows.map((r) => r['id'] as int).toList();
    final atts = await _attachmentsFor(conversationId, ids);
    return rows.map((r) => _fromRow(r, atts)).toList();
  }

  @override
  Future<void> replaceConversation(
      int conversationId, List<ChatMessage> messages) async {
    final db = await _open();
    await db.run(
      stores: [_messages, _attachments],
      write: true,
      body: (txn) async {
        final messagesStore = txn.objectStore(_messages);
        final attsStore = txn.objectStore(_attachments);
        await _deleteConversationRows(txn, conversationId);
        for (final m in messages) {
          await messagesStore.put(_toRow(m, conversationId));
          for (final a in m.attachments) {
            await attsStore.put({
              'conversation_id': conversationId,
              'message_id': m.id,
              'attachment_id': a.id,
              'data': jsonEncode(a.toJson()),
            });
          }
        }
      },
    );
  }

  @override
  Future<void> appendMessages(
      int conversationId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _open();
    await db.run(
      stores: [_messages, _attachments],
      write: true,
      body: (txn) async {
        final messagesStore = txn.objectStore(_messages);
        final attsStore = txn.objectStore(_attachments);
        for (final m in messages) {
          await messagesStore.put(_toRow(m, conversationId));
          await attsStore
              .delete(IdbKeys.conversationMessage(conversationId, m.id));
          for (final a in m.attachments) {
            await attsStore.put({
              'conversation_id': conversationId,
              'message_id': m.id,
              'attachment_id': a.id,
              'data': jsonEncode(a.toJson()),
            });
          }
        }
      },
    );
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    final db = await _open();
    await db.run(
      stores: [_messages, _attachments],
      write: true,
      body: (txn) async {
        final messagesStore = txn.objectStore(_messages);
        final attsStore = txn.objectStore(_attachments);
        await messagesStore.put(_toRow(message, message.conversationId));
        await attsStore.delete(IdbKeys.conversationMessage(
            message.conversationId, message.id));
        for (final a in message.attachments) {
          await attsStore.put({
            'conversation_id': message.conversationId,
            'message_id': message.id,
            'attachment_id': a.id,
            'data': jsonEncode(a.toJson()),
          });
        }
      },
    );
  }

  @override
  Future<void> deleteMessage(int conversationId, int messageId) async {
    final db = await _open();
    await db.run(
      stores: [_messages, _attachments],
      write: true,
      body: (txn) async {
        await txn.objectStore(_messages).delete([conversationId, messageId]);
        await txn
            .objectStore(_attachments)
            .delete(IdbKeys.conversationMessage(conversationId, messageId));
      },
    );
  }

  @override
  Future<void> deleteConversation(int conversationId) async {
    final db = await _open();
    await db.run(
      stores: [_messages, _attachments],
      write: true,
      body: (txn) async {
        await _deleteConversationRows(txn, conversationId);
      },
    );
  }

  /// Deletes every cached conversation and message from the local store
  /// (debug-menu wipe). Mirrors the IO implementation's clearAll.
  Future<void> clearAll() async {
    final db = await _open();
    await db.run(
      stores: [_messages, _attachments],
      write: true,
      body: (txn) async {
        await txn.objectStore(_messages).clear();
        await txn.objectStore(_attachments).clear();
      },
    );
  }

  Future<void> _deleteConversationRows(
      IdbTxn txn, int conversationId) async {
    final messagesStore = txn.objectStore(_messages);
    final attsStore = txn.objectStore(_attachments);
    final messageKeys = <Object>[];
    await messagesStore.openCursor(
      range: IdbKeys.conversation(conversationId),
      direction: 'next',
      onRow: (row) {
        messageKeys.add(row.key);
        return true;
      },
    );
    for (final key in messageKeys) {
      await messagesStore.delete(key);
    }
    final attKeys = <Object>[];
    await attsStore.openCursor(
      range: IdbKeys.conversation(conversationId),
      direction: 'next',
      onRow: (row) {
        attKeys.add(row.key);
        return true;
      },
    );
    for (final key in attKeys) {
      await attsStore.delete(key);
    }
  }

  Future<Map<int, List<Attachment>>> _attachmentsFor(
      int conversationId, List<int> messageIds) async {
    final byMsg = <int, List<Attachment>>{};
    if (messageIds.isEmpty) return byMsg;
    final db = await _open();
    await db.run(
      stores: [_attachments],
      write: false,
      body: (txn) async {
        final store = txn.objectStore(_attachments);
        for (final msgId in messageIds) {
          await store.openCursor(
            range: IdbKeys.conversationMessage(conversationId, msgId),
            direction: 'next',
            onRow: (row) {
              final v = row.value as Map;
              try {
                final map = jsonDecode(v['data'] as String);
                if (map is Map<String, dynamic>) {
                  byMsg.putIfAbsent(msgId, () => []).add(Attachment.fromJson(map));
                }
              } catch (_) {}
              return true;
            },
          );
        }
      },
    );
    return byMsg;
  }

  Map<String, Object?> _toRow(ChatMessage m, int conversationId) => {
        'id': m.id,
        'conversation_id': conversationId,
        'sender_id': m.senderId,
        'content': m.content,
        'kind': m.kind,
        'reply_to_id': m.replyToId,
        'edited_at': m.editedAt?.toIso8601String(),
        'deleted_at': m.deletedAt?.toIso8601String(),
        'created_at': m.createdAt.toIso8601String(),
        'sender_name': m.senderName,
        'sender_avatar': m.senderAvatar,
        'sender_verified': m.senderVerified,
        'client_id': m.clientId,
        'status': m.status.index,
        'decrypted_content': m.decryptedContent,
        'mentions': m.mentions.isEmpty ? null : jsonEncode(m.mentions),
      };

  ChatMessage _fromRow(Map r, Map<int, List<Attachment>> attsByMsg) {
    final statusRaw = r['status'] as int? ?? 2;
    final status = MessageStatus.values.length > statusRaw
        ? MessageStatus.values[statusRaw]
        : MessageStatus.sent;
    final rawMentions = r['mentions'];
    final mentions = rawMentions is String && rawMentions.isNotEmpty
        ? _parseMentions(rawMentions)
        : const <int>[];
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
      senderVerified: r['sender_verified'] == true,
      clientId: r['client_id'] as String?,
      status: status,
      decryptedContent: r['decrypted_content'] as String?,
      mentions: mentions,
      attachments: attsByMsg[r['id']] ?? const <Attachment>[],
    );
  }

  DateTime? _parseTime(Object? v) {
    if (v is String && v.isNotEmpty) {
      return DateTime.tryParse(v);
    }
    return null;
  }

  List<int> _parseMentions(String v) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is List) {
        return decoded.whereType<int>().toList();
      }
    } catch (_) {}
    return const [];
  }
}
