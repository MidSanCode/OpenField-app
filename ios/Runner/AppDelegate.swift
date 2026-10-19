import AVFoundation
import CallKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let callKit = CallKitBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // CallKit needs a channel per engine, so it is attached here rather than
    // through a separately registered plugin.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CallKitBridge") {
      callKit.attach(with: registrar)
    }
  }
}

/// Bridges the Dart call layer to CallKit, so an incoming call appears in the
/// system UI (lock screen, CarPlay, the Phone app's recents) the way a native
/// call does, and answering from there reaches the app.
///
/// Scope note: this reports calls while the app is alive — foreground or
/// backgrounded. Ringing a *terminated* app needs PushKit VoIP pushes, which
/// require an APNs VoIP certificate and a paid Apple Developer account; that is
/// deliberately not wired up yet.
final class CallKitBridge: NSObject, CXProviderDelegate {
  private static let channelName = "openfield/callkit"

  private var channel: FlutterMethodChannel?
  private let provider: CXProvider
  private let callController = CXCallController()
  /// Maps a CallKit UUID to the server-side call id, so an answer or hangup
  /// performed in the system UI can be routed back to the right call.
  private var serverCallIds: [UUID: Int] = [:]

  override init() {
    // The project deploys to iOS 13, so the localized initializer (iOS 14+) needs
    // a guarded fallback to the deprecated parameterless one.
    let configuration: CXProviderConfiguration
    if #available(iOS 14.0, *) {
      configuration = CXProviderConfiguration(localizedName: "OpenField")
    } else {
      configuration = CXProviderConfiguration()
    }
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic, .phoneNumber]
    provider = CXProvider(configuration: configuration)
    super.init()
    // nil queue: CallKit invokes the delegate on its own serial queue.
    provider.setDelegate(self, queue: nil)
  }

  /// Wires the bridge to a Flutter engine's messenger.
  func attach(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: CallKitBridge.channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "reportIncoming":
      reportIncoming(args)
      result(true)
    case "reportOutgoing":
      reportOutgoing(args)
      result(true)
    case "reportConnected":
      // The app answered in its own UI: dismiss the system call UI instead of
      // leaving a ringing banner nobody can answer any more.
      finish(callId: args["call_id"] as? Int, reason: .answeredElsewhere)
      result(true)
    case "end":
      finish(
        callId: args["call_id"] as? Int,
        reason: args["declined"] as? Bool == true ? .declinedElsewhere : .remoteEnded
      )
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func uuid(for callId: Int) -> UUID {
    if let existing = serverCallIds.first(where: { $0.value == callId })?.key {
      return existing
    }
    let uuid = UUID()
    serverCallIds[uuid] = callId
    return uuid
  }

  private func reportIncoming(_ args: [String: Any]) {
    guard let callId = args["call_id"] as? Int else { return }
    let handle = args["handle"] as? String ?? "OpenField"
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: handle)
    update.localizedCallerName = handle
    update.hasVideo = args["video"] as? Bool ?? false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    provider.reportNewIncomingCall(with: uuid(for: callId), update: update) { error in
      if let error = error {
        NSLog("[callkit] reportNewIncomingCall failed: \(error.localizedDescription)")
      }
    }
  }

  private func reportOutgoing(_ args: [String: Any]) {
    guard let callId = args["call_id"] as? Int else { return }
    let handle = CXHandle(type: .generic, value: args["handle"] as? String ?? "OpenField")
    let action = CXStartCallAction(call: uuid(for: callId), handle: handle)
    action.isVideo = args["video"] as? Bool ?? false
    callController.request(CXTransaction(action: action)) { error in
      if let error = error {
        NSLog("[callkit] start call transaction failed: \(error.localizedDescription)")
      }
    }
  }

  /// Tears the system call UI down for a call the app itself handled.
  private func finish(callId: Int?, reason: CXCallEndedReason) {
    guard let callId = callId,
      let uuid = serverCallIds.first(where: { $0.value == callId })?.key
    else { return }
    provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    serverCallIds.removeValue(forKey: uuid)
  }

  private func notifyDart(event: String, uuid: UUID) {
    guard let callId = serverCallIds[uuid] else { return }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod(
        "systemAction",
        arguments: ["event": event, "call_id": callId]
      )
    }
  }

  // MARK: - CXProviderDelegate

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    notifyDart(event: "answered", uuid: action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    notifyDart(event: "ended", uuid: action.callUUID)
    // Clear the system UI; the Dart side hangs up the server session in
    // response to the notification above.
    provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .remoteEnded)
    serverCallIds.removeValue(forKey: action.callUUID)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    // CallKit hands over an already-configured session; the app only has to
    // activate it. The category is left untouched: flutter_webrtc owns it.
    try? audioSession.setActive(true)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
  }
}
