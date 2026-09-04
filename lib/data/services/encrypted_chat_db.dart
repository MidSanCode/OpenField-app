/// Platform dispatch for the encrypted offline chat cache.
///
/// Both targets implement [ChatCacheStore]; the web one keeps the same
/// AES-256-GCM row sealing in IndexedDB that the SQLite one keeps on disk.
library;

export 'encrypted_chat_db_web.dart'
    if (dart.library.io) 'encrypted_chat_db_io.dart';
