/// Platform dispatch for the plugin engine.
///
/// flutter_js's QuickJS runtime is built on dart:ffi, which does not compile
/// for web. This barrel selects the real engine on IO platforms and a stub
/// on web, so the rest of the app keeps importing `plugin_engine.dart` and
/// web builds never see the ffi imports.
library;

export 'plugin_engine_stub.dart'
    if (dart.library.io) 'plugin_engine_io.dart';
