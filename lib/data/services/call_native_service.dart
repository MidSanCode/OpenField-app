import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Host-platform glue for calls: the Android foreground service that keeps a
/// call alive in the background, and the iOS CallKit integration that puts a
/// call into the system UI.
///
/// Both are best-effort. Every entry point degrades to a no-op when the platform
/// has no implementation (desktop, web) or the native handler is missing,
/// because a missing native nicety must never break the call itself.
class CallNativeService {
  CallNativeService._();

  /// Shared instance used by the call layer.
  static final CallNativeService instance = CallNativeService._();

  /// Channel implemented by `MainActivity.kt` (Android).
  static const MethodChannel _callChannel = MethodChannel('openfield/call');

  /// Channel implemented by `AppDelegate.swift` (iOS).
  static const MethodChannel _callKitChannel =
      MethodChannel('openfield/callkit');

  /// Invoked when the user answers from the iOS system call UI.
  void Function(int callId)? onSystemAnswered;

  /// Invoked when the user ends a call from the iOS system call UI.
  void Function(int callId)? onSystemEnded;

  bool _attached = false;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  bool get _isIOS => !kIsWeb && Platform.isIOS;

  /// Starts listening for system-UI call actions. Idempotent; iOS only.
  void attach() {
    if (_attached || !_isIOS) return;
    _attached = true;
    _callKitChannel.setMethodCallHandler((call) async {
      if (call.method != 'systemAction') return null;
      final args = call.arguments;
      if (args is! Map) return null;
      final callId = (args['call_id'] as num?)?.toInt() ?? 0;
      if (callId == 0) return null;
      switch (args['event']) {
        case 'answered':
          onSystemAnswered?.call(callId);
          break;
        case 'ended':
          onSystemEnded?.call(callId);
          break;
      }
      return null;
    });
  }

  /// Reports an incoming call to CallKit so the system shows its call UI.
  Future<void> reportIncoming({
    required int callId,
    required String handle,
    bool video = false,
  }) =>
      _invoke(_callKitChannel, 'reportIncoming', {
        'call_id': callId,
        'handle': handle,
        'video': video,
      });

  /// Reports an outgoing call, which puts it into the phone's recents.
  Future<void> reportOutgoing({
    required int callId,
    required String handle,
    bool video = false,
  }) =>
      _invoke(_callKitChannel, 'reportOutgoing', {
        'call_id': callId,
        'handle': handle,
        'video': video,
      });

  /// Tells CallKit the app answered in its own UI, so the system banner goes
  /// away instead of offering an answer that already happened.
  Future<void> reportConnected(int callId) =>
      _invoke(_callKitChannel, 'reportConnected', {'call_id': callId});

  /// Clears the system call UI for a call that finished.
  Future<void> endSystemCall({required int callId, bool declined = false}) =>
      _invoke(_callKitChannel, 'end', {
        'call_id': callId,
        'declined': declined,
      });

  /// Keeps a live call alive while the app is backgrounded (Android only).
  Future<void> startOngoingCall(String title) =>
      _isAndroid ? _invoke(_callChannel, 'startForeground', {'title': title}) : Future<void>.value();

  /// Drops the ongoing-call notification (Android only).
  Future<void> stopOngoingCall() =>
      _isAndroid ? _invoke(_callChannel, 'stopForeground', {}) : Future<void>.value();

  Future<void> _invoke(
    MethodChannel channel,
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      await channel.invokeMethod<Object?>(method, arguments);
    } catch (e) {
      // MissingPluginException on platforms without the handler, or a native
      // failure: log and carry on with the call.
      debugPrint('[call] native "$method" unavailable: $e');
    }
  }
}
