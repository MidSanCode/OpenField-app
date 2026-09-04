/// Platform dispatch for the offline chat cache.
///
/// On IO platforms messages live in SQLite (sqflite_ffi); on web the same
/// cache lands in IndexedDB (chat_local_db_web.dart, selected through the
/// dart.library.html condition — the same shape as main.dart's history
/// import). The default branch must stay platform-free-compilable: the VM
/// CFE only loads the selected branch, but the file referenced as the
/// fallback is still type-checked on every target, so it must never import
/// web-only libraries. MLS-encrypted conversations get a dedicated encrypted
/// store on both platform families (see encrypted_chat_db.dart).
library;

export 'chat_local_db_io.dart'
    if (dart.library.html) 'chat_local_db_web.dart';
