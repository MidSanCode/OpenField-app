/// Platform dispatch for the encrypted offline chat cache.
///
/// On IO platforms rows live in SQLite; on web the same AES-256-GCM row
/// sealing lands in IndexedDB (encrypted_chat_db_web.dart, selected through
/// the dart.library.html condition — the same shape as main.dart's history
/// import). The default branch must stay platform-free-compilable, so the
/// web file may never be the fallback. Both targets implement
/// [ChatCacheStore].
library;

export 'encrypted_chat_db_io.dart'
    if (dart.library.html) 'encrypted_chat_db_web.dart';
