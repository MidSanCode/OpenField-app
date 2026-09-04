import 'dart:typed_data';

import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/services/chat_cache_store.dart';
import 'package:openfield/data/services/e2ee_service.dart';
import 'package:openfield/data/services/encrypted_chat_payload.dart';
import 'package:openfield/data/services/idb_database.dart';

/// IndexedDB cache for messages of MLS-encrypted conversations (web).
///
/// Keeps the same security shape as the SQLite target on IO platforms: rows
/// carry only the id / conversation / timestamp needed for ordering and
/// pagination in clear, while everything sensitive — decrypted plaintext,
/// mentions, attachments — is sealed in an AES-256-GCM `payload` blob under a
/// key derived from the user's E2EE identity private key. The store therefore
/// cannot be read without that key, and logging in as a different account
/// makes any leftover rows undecryptable placeholders.
class EncryptedChatDb implements ChatCacheStore {
  EncryptedChatDb._();

  static final EncryptedChatDb instance = EncryptedChatDb._();

  IdbDatabase? _db;
  Uint8List? _key;

  /// The web build always supports the IndexedDB cache.
  static bool get supported => true;

  static const _store = 'messages';

  Future<IdbDatabase> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await IdbDatabase.open(
      name: 'openfield_e2ee',
      version: 1,
      onUpgradeNeeded: (txn, oldVersion, newVersion) {
        if (oldVersion < 1) {
          txn.objectStore(_store, createIfMissing: true);
        }
      },
    );
    _db = db;
    return db;
  }

  /// The AES key that seals this store, derived from the E2EE identity. Null
  /// while no identity exists (fresh browser profile / before first ensure) —
  /// reads then return nothing and writes are skipped rather than storing
  /// plaintext.
  Future<Uint8List?> _keyOrNull() async {
    if (_key != null) return _key;
    final key = await E2eeService.instance.storageKey();
    if (key != null) _key = key;
    return key;
  }

  @override
  Future<int?> minMessageId(int conversationId) async {
    final db = await _open();
    if (await _keyOrNull() == null) return null;
    int? minId;
    await db.run(
      stores: [_store],
      write: false,
      body: (txn) async {
        await txn.objectStore(_store).openCursor(
              range: IdbKeys.conversation(conversationId),
              direction: 'next',
              onRow: (row) {
                minId = (row.value as Map)['id'] as int?;
                return false;
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
    final key = await _keyOrNull();
    if (key == null) return const [];
    final rows = <Map>[];
    await db.run(
      stores: [_store],
      write: false,
      body: (txn) async {
        await txn.objectStore(_store).openCursor(
              range: beforeId != null
                  ? IdbKeys.conversationBefore(conversationId, beforeId)
                  : IdbKeys.conversation(conversationId),
              direction: 'prev',
              onRow: (row) {
                rows.add(row.value as Map);
                return rows.length < limit;
              },
            );
      },
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
    final key = await _keyOrNull();
    if (key == null) return const [];
    final rows = <Map>[];
    await db.run(
      stores: [_store],
      write: false,
      body: (txn) async {
        await txn.objectStore(_store).openCursor(
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
    return rows.map((r) => _fromRow(r, key)).toList();
  }

  @override
  Future<void> replaceConversation(
      int conversationId, List<ChatMessage> messages) async {
    final db = await _open();
    final key = await _keyOrNull();
    if (key == null) return;
    await db.run(
      stores: [_store],
      write: true,
      body: (txn) async {
        final store = txn.objectStore(_store);
        final doomed = <Object>[];
        await store.openCursor(
          range: IdbKeys.conversation(conversationId),
          direction: 'next',
          onRow: (row) {
            doomed.add(row.key);
            return true;
          },
        );
        for (final k in doomed) {
          await store.delete(k);
        }
        for (final m in messages) {
          await _insert(store, m, conversationId, key);
        }
      },
    );
  }

  @override
  Future<void> appendMessages(
      int conversationId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _open();
    final key = await _keyOrNull();
    if (key == null) return;
    await db.run(
      stores: [_store],
      write: true,
      body: (txn) async {
        final store = txn.objectStore(_store);
        for (final m in messages) {
          await _insert(store, m, conversationId, key);
        }
      },
    );
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    final db = await _open();
    final key = await _keyOrNull();
    if (key == null) return;
    await db.run(
      stores: [_store],
      write: true,
      body: (txn) async {
        await _insert(txn.objectStore(_store), message, message.conversationId,
            key);
      },
    );
  }

  Future<void> _insert(
      IdbStore store, ChatMessage m, int conversationId, Uint8List key) async {
    final payload = sealMessagePayload(m, key);
    if (payload == null) return;
    await store.put({
      'id': m.id,
      'conversation_id': conversationId,
      'created_at': m.createdAt.toIso8601String(),
      'payload': payload,
    }, [conversationId, m.id]);
  }

  @override
  Future<void> deleteMessage(int conversationId, int messageId) async {
    final db = await _open();
    await db.run(
      stores: [_store],
      write: true,
      body: (txn) async {
        await txn.objectStore(_store).delete([conversationId, messageId]);
      },
    );
  }

  @override
  Future<void> deleteConversation(int conversationId) async {
    final db = await _open();
    await db.run(
      stores: [_store],
      write: true,
      body: (txn) async {
        final store = txn.objectStore(_store);
        final doomed = <Object>[];
        await store.openCursor(
          range: IdbKeys.conversation(conversationId),
          direction: 'next',
          onRow: (row) {
            doomed.add(row.key);
            return true;
          },
        );
        for (final k in doomed) {
          await store.delete(k);
        }
      },
    );
  }

  ChatMessage _fromRow(Map r, Uint8List key) {
    final id = r['id'] as int;
    final conversationId = r['conversation_id'] as int;
    final createdAt = DateTime.parse(r['created_at'] as String);
    return openMessagePayload(
        r['payload'], key, id, conversationId, createdAt);
  }
}
