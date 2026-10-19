import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:openfield/data/models/call_session.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/realtime_service.dart';

/// Lifecycle of the call shown in the UI.
///
/// [dialing] and [ringing] are the two ringing roles (caller vs callee),
/// [connecting] means the call was accepted and negotiation is under way, and
/// [active] means media is flowing.
enum CallPhase { idle, dialing, ringing, connecting, active, ended }

/// Drives peer-to-peer voice/video calls on the client.
///
/// The server owns the call state machine (see `docs/calls.md` in the server
/// repo) and relays signalling; media goes straight between the two peers, so
/// this service is where the WebRTC side lives:
///
///   POST /calls → offer → POST /calls/:id/signal (offer)
///   call.signal (answer) → POST /calls/:id/signal (candidates) → connected
///
/// Signalling travels over REST rather than the push WebSocket because that
/// socket is downstream-only: the client cannot write frames up it.
class CallService extends ChangeNotifier {
  /// Process-wide singleton; the call overlay listens to this instance.
  static final CallService instance = CallService._();

  CallService._();

  /// STUN servers used to discover the peers' public addresses.
  ///
  /// STUN alone connects only when neither side sits behind a symmetric NAT.
  /// Production deployments must add a TURN server through [setTurnServers] or
  /// a share of calls will fail to connect on mobile networks and corporate
  /// networks (see the server's docs/calls.md).
  static List<Map<String, dynamic>> iceServers = <Map<String, dynamic>>[
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  /// Adds TURN relay servers, e.g. `{'urls': 'turn:host:3478', 'username':
  /// 'user', 'credential': 'secret'}`. Called from settings once a TURN
  /// deployment exists.
  static void setTurnServers(List<Map<String, dynamic>> servers) {
    iceServers = [
      ...iceServers.where((s) => !s['urls'].toString().startsWith('turn:')),
      ...servers,
    ];
  }

  final ApiService _api = ApiService();

  CallPhase _phase = CallPhase.idle;
  CallSession? _session;
  int _peerUserId = 0;
  String _peerName = '';
  String? _peerAvatar;
  bool _isCaller = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _video = false;
  String? _error;
  String _endReason = '';
  Duration _elapsed = Duration.zero;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _hasRemoteDescription = false;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];

  String? _accessToken;
  StreamSubscription<PushEvent>? _eventSub;
  Timer? _elapsedTimer;
  Timer? _resetTimer;
  bool _teardownDone = false;

  /// Current phase of the overlay.
  CallPhase get phase => _phase;

  /// True while the overlay should be mounted.
  bool get isVisible => _phase != CallPhase.idle;

  /// Server-side call record; null before the server answered.
  CallSession? get session => _session;

  /// Peer's user id (0 while unknown).
  int get peerUserId => _peerUserId;

  /// Peer's display name for the call UI.
  String get peerName => _peerName;

  /// Peer's avatar URL, when known.
  String? get peerAvatar => _peerAvatar;

  /// True when this device placed the call.
  bool get isCaller => _isCaller;

  /// True when the outgoing call is still ringing on the peer's side.
  bool get isDialing => _phase == CallPhase.dialing;

  /// True when this device is ringing for an incoming call.
  bool get isRinging => _phase == CallPhase.ringing;

  /// True once the call is connected and media flows.
  bool get isActive => _phase == CallPhase.active;

  /// True when video was requested for this call.
  bool get isVideo => _video;

  /// Microphone mute state.
  bool get isMuted => _muted;

  /// Speakerphone state (audio calls only).
  bool get isSpeakerOn => _speakerOn;

  /// Time since the call connected.
  Duration get elapsed => _elapsed;

  /// User-facing failure message, when the last attempt failed.
  String? get error => _error;

  /// Why the call ended (`hung_up`, `declined`, `timeout`, ...).
  String get endReason => _endReason;

  /// Binds the signed-in token and starts routing call pushes. Called from the
  /// app root whenever auth changes; a null token tears any live call down.
  void updateSession(String? token) {
    if (_accessToken == token) {
      _attachEvents();
      return;
    }
    _accessToken = token;
    if (token == null) {
      if (_phase != CallPhase.idle) {
        _teardown();
        _resetToIdle();
      }
      _eventSub?.cancel();
      _eventSub = null;
      return;
    }
    _attachEvents();
  }

  void _attachEvents() {
    if (_eventSub != null) return;
    _eventSub = RealtimeService.instance.events.listen(_onPushEvent);
  }

  /// Places a call inside a one-to-one conversation.
  ///
  /// [peerUserId], [peerName] and [peerAvatar] are display data used by the
  /// overlay; the server derives the real peer from the conversation.
  Future<void> startCall({
    required int conversationId,
    required int peerUserId,
    required String peerName,
    String? peerAvatar,
    bool video = false,
  }) async {
    if (_phase != CallPhase.idle) return;
    final token = _accessToken;
    if (token == null) {
      _fail('not signed in');
      return;
    }

    _resetToIdle();
    _isCaller = true;
    _video = video;
    _peerUserId = peerUserId;
    _peerName = peerName;
    _peerAvatar = peerAvatar;
    _error = null;
    _phase = CallPhase.dialing;
    notifyListeners();

    if (!await _ensureMicrophonePermission()) {
      _fail('microphone permission denied');
      return;
    }

    try {
      final call = await _api.startCall(token, conversationId,
          mode: video ? 'video' : 'audio');
      _session = call;
      notifyListeners();

      await _ensurePeerConnection();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _sendSignal(token, call.id, 'offer', {
        'type': offer.type,
        'sdp': offer.sdp,
      });
    } catch (e) {
      _fail(e is ApiException ? e.message : 'could not place the call');
    }
  }

  /// Accepts the ringing call and starts negotiating.
  Future<void> accept() async {
    final token = _accessToken;
    final session = _session;
    if (token == null || session == null || _phase != CallPhase.ringing) return;

    _error = null;
    _phase = CallPhase.connecting;
    notifyListeners();

    if (!await _ensureMicrophonePermission()) {
      _fail('microphone permission denied');
      await _safeDecline(token, session.id);
      return;
    }

    try {
      await _api.answerCall(token, session.id);
      await _ensurePeerConnection();
    } catch (e) {
      // 409 means another device answered first: stop ringing quietly instead
      // of showing an error for a call this device simply lost.
      if (e is ApiException && e.statusCode == 409) {
        _teardown();
        _resetToIdle();
        return;
      }
      _fail(e is ApiException ? e.message : 'could not answer the call');
    }
  }

  /// Rejects the ringing call.
  Future<void> decline() async {
    final token = _accessToken;
    final session = _session;
    if (token == null || session == null) {
      _resetToIdle();
      return;
    }
    await _safeDecline(token, session.id);
    _teardown();
    _resetToIdle();
  }

  /// Ends the call from either side (cancels while ringing).
  Future<void> hangup() async {
    final token = _accessToken;
    final session = _session;
    if (token != null && session != null) {
      try {
        await _api.hangupCall(token, session.id);
      } catch (e) {
        debugPrint('[call] hangup failed: $e');
      }
    }
    _teardown();
    _resetToIdle();
  }

  /// Toggles the local microphone.
  Future<void> toggleMute() async {
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    _muted = !_muted;
    for (final track in tracks) {
      // flutter_webrtc exposes mute as a settable property, not a method.
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  /// Toggles the speakerphone (audio calls; a no-op where the platform has no
  /// concept of it, e.g. desktop output selection).
  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    notifyListeners();
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (e) {
      debugPrint('[call] speaker toggle unsupported: $e');
    }
  }

  /// Reconciles with the server when a chat is opened, so a call whose push
  /// event was missed (offline, app restarted) still surfaces as ringing.
  ///
  /// Only ringing invitations are recovered: an already-connected call cannot be
  /// rejoined without renegotiating media, so pretending otherwise would leave a
  /// dead call UI on screen.
  Future<void> syncConversation(int conversationId, {int myUserId = 0}) async {
    final token = _accessToken;
    if (token == null || _phase != CallPhase.idle) return;
    try {
      final live = await _api.getActiveCall(token, conversationId);
      if (live == null || !live.isRinging || _phase != CallPhase.idle) return;
      if (myUserId != 0 && live.initiatorId == myUserId) return;
      _session = live;
      _isCaller = false;
      _video = live.isVideo;
      _peerUserId = live.initiatorId;
      _phase = CallPhase.ringing;
      notifyListeners();
      _resolvePeerProfile(live.initiatorId);
    } catch (e) {
      debugPrint('[call] state sync failed: $e');
    }
  }

  // ---- push events ----

  void _onPushEvent(PushEvent event) {
    if (!event.type.startsWith('call.')) return;
    final callId = _asInt(event.data['call_id']);
    if (callId == 0) return;

    switch (event.type) {
      case 'call.invited':
        _onInvited(callId, event.data);
        break;
      case 'call.accepted':
        // The callee's other devices (and a caller already in `connecting`) use
        // this to stop ringing; only the device that answered keeps going.
        if (_phase == CallPhase.ringing) {
          _teardown();
          _resetToIdle();
        } else if (_isCaller && _phase == CallPhase.dialing) {
          _phase = CallPhase.connecting;
          notifyListeners();
        }
        break;
      case 'call.declined':
        if (_isCaller && _session?.id == callId) {
          _endReason = 'declined';
          _finish();
        }
        break;
      case 'call.ended':
        if (_session?.id == callId) {
          _endReason = event.data['end_reason']?.toString() ?? '';
          _finish();
        }
        break;
      case 'call.signal':
        if (_session?.id == callId) {
          _handleSignal(event.data);
        }
        break;
    }
  }

  void _onInvited(int callId, Map<String, dynamic> data) {
    // Already busy: reject the new call instead of dropping the current one.
    if (_phase != CallPhase.idle) {
      final token = _accessToken;
      if (token != null) _safeDecline(token, callId);
      return;
    }
    final initiator = _asInt(data['initiator_id']);
    if (initiator == 0) return;

    _session = CallSession(
      id: callId,
      conversationId: _asInt(data['conversation_id']),
      initiatorId: initiator,
      mode: data['mode']?.toString() ?? 'audio',
      state: 'ringing',
      endReason: '',
      durationSeconds: 0,
    );
    _isCaller = false;
    _video = _session!.isVideo;
    _peerUserId = initiator;
    _error = null;
    _endReason = '';
    _phase = CallPhase.ringing;
    notifyListeners();
    // The invite carries no display data, so fetch the caller's profile for the
    // ringing UI (best effort: a failure just leaves the name empty).
    _resolvePeerProfile(initiator);
  }

  /// Loads the peer's display name and avatar for the call overlay.
  Future<void> _resolvePeerProfile(int userId) async {
    final token = _accessToken;
    if (token == null || userId == 0) return;
    try {
      final user = await _api.getUser(userId, token: token);
      if (_peerUserId != userId) return;
      _peerName = user.nickname.isNotEmpty ? user.nickname : user.username;
      _peerAvatar = user.avatarUrl.isNotEmpty ? user.avatarUrl : null;
      notifyListeners();
    } catch (e) {
      debugPrint('[call] could not load the peer profile: $e');
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    final from = _asInt(data['from_user_id']);
    if (from != 0) _peerUserId = from;
    final payload = data['payload'];
    if (payload is! Map) return;
    final map = Map<String, dynamic>.from(payload);

    try {
      switch (type) {
        case 'offer':
          if (_phase != CallPhase.connecting && _phase != CallPhase.active) {
            return;
          }
          await _ensurePeerConnection();
          final description = RTCSessionDescription(
            map['sdp']?.toString(),
            map['type']?.toString() ?? 'offer',
          );
          await _pc!.setRemoteDescription(description);
          _hasRemoteDescription = true;
          await _flushPendingCandidates();
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          final token = _accessToken;
          if (token != null) {
            await _sendSignal(token, _session!.id, 'answer', {
              'type': answer.type,
              'sdp': answer.sdp,
            });
          }
          notifyListeners();
          break;
        case 'answer':
          if (_pc == null) return;
          await _pc!.setRemoteDescription(
            RTCSessionDescription(
              map['sdp']?.toString(),
              map['type']?.toString() ?? 'answer',
            ),
          );
          _hasRemoteDescription = true;
          await _flushPendingCandidates();
          break;
        case 'candidate':
          final candidate = RTCIceCandidate(
            map['candidate']?.toString(),
            map['sdpMid']?.toString(),
            _asInt(map['sdpMLineIndex']),
          );
          if (_hasRemoteDescription && _pc != null) {
            await _pc!.addCandidate(candidate);
          } else {
            _pendingCandidates.add(candidate);
          }
          break;
      }
    } catch (e) {
      debugPrint('[call] signalling failed ($type): $e');
    }
  }

  Future<void> _flushPendingCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final candidate in _pendingCandidates) {
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('[call] buffered candidate rejected: $e');
      }
    }
    _pendingCandidates.clear();
  }

  // ---- WebRTC plumbing ----

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;

    _hasRemoteDescription = false;
    _pendingCandidates.clear();

    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc.onIceCandidate = (candidate) {
      final token = _accessToken;
      final session = _session;
      if (token == null || session == null) return;
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      _sendSignal(token, session.id, 'candidate', {
        'candidate': value,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (_phase != CallPhase.active) {
          _phase = CallPhase.active;
          _startElapsedTimer();
          notifyListeners();
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endReason = 'connection_failed';
        _finish();
      }
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        notifyListeners();
      }
    };

    _pc = pc;

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': _video
          ? {'facingMode': 'user', 'width': 1280, 'height': 720}
          : false,
    });
    _localStream = stream;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    // Audio-only calls default to the earpiece on phones, video to speaker.
    try {
      await Helper.setSpeakerphoneOn(_video);
      _speakerOn = _video;
    } catch (e) {
      debugPrint('[call] speaker init unsupported: $e');
    }
  }

  Future<void> _sendSignal(
    String token,
    int callId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _api.sendCallSignal(token, callId, type: type, payload: payload);
    } catch (e) {
      debugPrint('[call] failed to relay $type: $e');
    }
  }

  Future<void> _safeDecline(String token, int callId) async {
    try {
      await _api.declineCall(token, callId);
    } catch (e) {
      debugPrint('[call] decline failed: $e');
    }
  }

  Future<bool> _ensureMicrophonePermission() async {
    // Browsers and desktop WebRTC prompt on their own; the permission_handler
    // API is not implemented on every desktop platform, so a failure there must
    // not block a call that could otherwise succeed.
    if (kIsWeb) return true;
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) return true;
      final requested = await Permission.microphone.request();
      if (requested.isGranted) return true;
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  // ---- lifecycle ----

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsed = Duration.zero;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  /// Marks the call as finished, shows the outcome briefly, then resets.
  void _finish() {
    _teardown();
    if (_phase == CallPhase.idle) return;
    _phase = CallPhase.ended;
    notifyListeners();
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1600), _resetToIdle);
  }

  void _fail(String message) {
    _error = message;
    _endReason = 'failed';
    _finish();
  }

  /// Releases the peer connection and media. Deliberately synchronous: callers
  /// (reset, failure, hangup) must not race an in-flight async teardown, so the
  /// closing futures are detached instead of awaited.
  void _teardown() {
    if (_teardownDone) return;
    _teardownDone = true;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _pendingCandidates.clear();
    _hasRemoteDescription = false;

    final local = _localStream;
    _localStream = null;
    if (local != null) {
      for (final track in local.getTracks()) {
        unawaited(Future.sync(track.stop).catchError((Object _) {}));
      }
      unawaited(Future.sync(local.dispose).catchError((Object _) {}));
    }

    final remote = _remoteStream;
    _remoteStream = null;
    if (remote != null) {
      unawaited(Future.sync(remote.dispose).catchError((Object _) {}));
    }

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      unawaited(Future.sync(pc.close).catchError((Object _) {}));
    }
  }

  void _resetToIdle() {
    _resetTimer?.cancel();
    _resetTimer = null;
    _teardown();
    _teardownDone = false;
    _phase = CallPhase.idle;
    _session = null;
    _peerUserId = 0;
    _peerName = '';
    _peerAvatar = null;
    _isCaller = false;
    _muted = false;
    _speakerOn = false;
    _video = false;
    _error = null;
    _endReason = '';
    _elapsed = Duration.zero;
    notifyListeners();
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _resetTimer?.cancel();
    _elapsedTimer?.cancel();
    _teardown();
    super.dispose();
  }
}
