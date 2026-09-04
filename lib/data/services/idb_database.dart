// Web-only file: imported exclusively through conditional exports selected
// by dart.library.html, so the VM/desktop toolchain never compiles it. The
// ignore list keeps `dart analyze` quiet on desktop SDKs, where the SDK
// metadata does not declare dart:indexed_db even though the source ships.
// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:indexed_db' as idb;

/// Minimal typed wrapper over dart:indexed_db used by the web chat caches.
///
/// Every store operation runs inside its own transaction unless the caller
/// explicitly groups work through [IdbDatabase.run]; IndexedDB commits a
/// transaction once its last request settles, and issuing the next request
/// from an await continuation (a microtask) keeps the same transaction alive,
/// so plain sequential awaits inside [run] are safe as long as no unrelated
/// async work (timers, I/O, network) slips in between them.
class IdbDatabase {
  final idb.Database _raw;

  IdbDatabase._(this._raw);

  List<String> get storeNames => _raw.objectStoreNames ?? const [];

  /// Opens (creating or upgrading as needed) the named database.
  static Future<IdbDatabase> open({
    required String name,
    required int version,
    void Function(IdbVersionChangeTxn txn, int oldVersion, int newVersion)?
        onUpgradeNeeded,
  }) async {
    final factory = html.window.indexedDB;
    if (factory == null) {
      throw UnsupportedError('IndexedDB is not available in this browser');
    }
    final raw = await factory.open(
      name,
      version: version,
      onUpgradeNeeded: onUpgradeNeeded == null
          ? null
          : (event) {
              // The upgrade transaction hangs off the request, not the event.
              final request = event.target;
              final txn = IdbVersionChangeTxn._(
                  request.transaction!, request.result as idb.Database);
              onUpgradeNeeded(txn, event.oldVersion ?? 0, event.newVersion ?? 0);
            },
    );
    return IdbDatabase._(raw);
  }

  /// Runs [body] inside one transaction over [stores].
  Future<T> run<T>({
    required List<String> stores,
    required bool write,
    required Future<T> Function(IdbTxn txn) body,
  }) async {
    final txn = _raw.transaction(stores, write ? 'readwrite' : 'readonly');
    return body(IdbTxn._(txn));
  }
}

/// A schema-upgrade transaction; object stores may only be created here.
class IdbVersionChangeTxn {
  final idb.Transaction _raw;
  final idb.Database db;

  IdbVersionChangeTxn._(this._raw, this.db);

  /// Returns an upgrade-scoped handle to [name], creating the store when it
  /// does not exist yet.
  IdbUpgradeStore objectStore(String name, {bool createIfMissing = false}) {
    if (createIfMissing && !(db.objectStoreNames?.contains(name) ?? false)) {
      return IdbUpgradeStore._(db.createObjectStore(name));
    }
    return IdbUpgradeStore._(_raw.objectStore(name));
  }
}

class IdbUpgradeStore {
  final idb.ObjectStore _raw;

  IdbUpgradeStore._(this._raw);

  /// Creates an index over [keyPath] inside the object store.
  void createIndex(String name, List<String> keyPath) {
    _raw.createIndex(name, keyPath);
  }
}

/// A read/write transaction handle yielding object stores.
class IdbTxn {
  final idb.Transaction _raw;

  IdbTxn._(this._raw);

  IdbStore objectStore(String name) => IdbStore._(_raw.objectStore(name));
}

/// Wrapper around one object store bound to an existing transaction.
class IdbStore {
  final idb.ObjectStore _raw;

  IdbStore._(this._raw);

  Future<Object?> get(Object key) => _raw.getObject(key);

  Future<Object?> put(Object value, [Object? key]) =>
      key == null ? _raw.put(value) : _raw.put(value, key);

  Future<Object?> add(Object value, [Object? key]) =>
      key == null ? _raw.add(value) : _raw.add(value, key);

  Future<Object?> delete(Object key) => _raw.delete(key);

  Future<void> clear() async {
    await _raw.clear();
  }

  /// Iterates the store with a cursor. [direction] is 'next' or 'prev';
  /// [onRow] returns false to stop early. With [autoAdvance] the SDK advances
  /// the cursor after each listener call, so the stream simply yields every
  /// matching row in key order.
  Future<void> openCursor({
    Object? range,
    required String direction,
    required FutureOr<bool> Function(IdbCursorRow row) onRow,
  }) async {
    final stream = _raw.openCursor(
      range: range as idb.KeyRange?,
      direction: direction,
      autoAdvance: true,
    );
    await for (final cursor in stream) {
      final row = IdbCursorRow._(cursor.key ?? Object(),
          cursor.value ?? Object());
      if (!await onRow(row)) break;
    }
  }
}

/// One cursor position: the primary key and the stored value.
class IdbCursorRow {
  final Object key;
  final Object value;

  IdbCursorRow._(this.key, this.value);
}

/// Key-range helpers for the composite keys the chat caches use.
///
/// IndexedDB compares array keys element-wise and treats a shorter array as
/// smaller when it is a prefix of the longer one, so the range
/// `[[conv], [conv+1])` covers exactly the keys whose first element is
/// [conv], regardless of how many trailing key elements exist.
class IdbKeys {
  IdbKeys._();

  /// Every key whose first element is [conversationId].
  static Object conversation(int conversationId) =>
      idb.KeyRange.bound([conversationId], [conversationId + 1], false, true);

  /// Keys `[conversationId, second]` with second <= [maxSecond] (inclusive).
  static Object conversationUpTo(int conversationId, int maxSecond) =>
      idb.KeyRange.bound(
          [conversationId], [conversationId, maxSecond], false, false);

  /// Keys `[conversationId, second]` with second < [maxSecond] (exclusive).
  static Object conversationBefore(int conversationId, int maxSecond) =>
      idb.KeyRange.bound(
          [conversationId], [conversationId, maxSecond], false, true);

  /// Keys `[conversationId, second]` with second > [minSecond] (exclusive).
  static Object conversationFrom(int conversationId, int minSecond) =>
      idb.KeyRange.bound(
          [conversationId, minSecond], [conversationId + 1], true, true);

  /// Keys `[conversationId, second]` with second >= [minSecond] (inclusive).
  static Object conversationFromInclusive(
          int conversationId, int minSecond) =>
      idb.KeyRange.bound(
          [conversationId, minSecond], [conversationId + 1], false, true);

  /// All three-part keys `[conversationId, messageId, *]`.
  static Object conversationMessage(int conversationId, int messageId) =>
      idb.KeyRange.bound(
          [conversationId, messageId], [conversationId, messageId + 1],
          false, true);
}
