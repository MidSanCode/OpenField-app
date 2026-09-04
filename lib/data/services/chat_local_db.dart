/// Platform dispatch for the offline chat cache.
///
/// On IO platforms messages live in SQLite (sqflite_ffi); on web the same
/// cache lands in IndexedDB (chat_local_db_web.dart is the default target).
/// MLS-encrypted conversations get a dedicated encrypted store on both
/// platform families (see encrypted_chat_db.dart).
library;

export 'chat_local_db_web.dart'
    if (dart.library.html) 'chat_local_db_io.dart';
