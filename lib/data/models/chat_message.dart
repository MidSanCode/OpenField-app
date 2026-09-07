import 'dart:convert';
import 'dart:math';
import 'attachment.dart';

/// How a message relates to the server. [sent] is confirmed; [sending] and
/// [failed] are local-only states for optimistic UI.
enum MessageStatus { sending, sent, failed }

/// A chat message: text or a system event, with reply metadata, sender
/// profile/styling, attachments, E2EE state and burn-after-read info.
class ChatMessage {
  /// Server-assigned message id; 0 for optimistic local sends that have not
  /// been confirmed yet (see [isLocal]).
  final int id;
  /// Conversation the message belongs to.
  final int conversationId;
  /// Sender's user id.
  final int senderId;
  /// Raw body text; for E2EE conversations this holds the ciphertext envelope
  /// until decrypted (see [decryptedContent] and [displayContent]).
  final String content;

  /// Server-side message kind: 'text' or system kinds such as
  /// 'system.join' / 'system.leave' / 'system.mute' / 'system.unmute' /
  /// 'system.mute.all' / 'system.unmute.all'.
  final String kind;
  /// Id of the message this one replies to; null when not a reply.
  final int? replyToId;
  /// Sender name of the replied-to message (denormalized for the reply
  /// preview).
  final String? replyToName;
  /// Content snippet of the replied-to message (denormalized for the reply
  /// preview).
  final String? replyToContent;
  /// When the message was last edited; null when never edited.
  final DateTime? editedAt;
  /// When the message was deleted; null while it still exists.
  final DateTime? deletedAt;
  /// When the message was created (server timestamp).
  final DateTime createdAt;

  /// For kind == 'check' messages: the id of the attached check. Fetch the
  /// full check (amount, claims, status) from /checks/:id before rendering.
  final int checkId;
  /// Sender's display name, when the payload includes it.
  final String? senderName;
  /// Sender's avatar URL, when the payload includes it.
  final String? senderAvatar;
  /// Whether the sender carries a verification badge.
  final bool senderVerified;
  /// Whether the sender is a bot account.
  final bool senderIsBot;
  /// Sender's membership tier (0 = none).
  final int senderMemberLevel;
  /// Whether the sender's membership is currently active.
  final bool senderMemberActive;
  /// Sender's name colour as a hex string ('' = default rendering).
  final String senderNameColor;
  /// Second name colour for gradients ('' = none).
  final String senderNameColorTo;
  /// Whether the sender's name colour animates over time.
  final bool senderNameDynamic;
  /// Palette for dynamic names; empty = use [senderNameColor]/
  /// [senderNameColorTo].
  final List<String> senderNameColors;
  /// Gradient direction hint for the name colours ('' = default).
  final String senderNameGradientDirection;
  /// Sender's avatar frame asset key ('' = no frame).
  final String senderAvatarFrame;
  /// Media attached to the message; empty for text-only messages.
  final List<Attachment> attachments;

  /// Server-confirmed user IDs explicitly @-mentioned in this message. The
  /// sentinel [-1] marks an @everyone mention. Sent by the sender so other
  /// clients can highlight/notify the right people.
  final List<int> mentions;

  /// Local, client-generated identity used to track a message before the
  /// server assigns an [id] (optimistic sends) and to keep ordering stable.
  final String clientId;

  /// Local send state. Only meaningful for the current user's own messages.
  final MessageStatus status;

  /// The decrypted plaintext of an end-to-end-encrypted message, populated
  /// locally after a successful decrypt. When null, [content] holds the
  /// ciphertext envelope (for encrypted conversations).
  final String? decryptedContent;

  /// Transient attachment-upload progress for optimistic messages, in [0, 1].
  /// Never serialized or persisted: it only lives on the locally created
  /// message while its file is still uploading.
  final double? uploadProgress;

  /// Burn-after-read countdown armed on this message, in seconds. 0 = the
  /// message never burns. The absolute deadline lives in [burnAt]; it is set
  /// the first time a recipient (never the sender) reads the message.
  final int burnSeconds;

  /// The instant this message will burn (soft-deleted server-side and dropped
  /// by every client). Null while nobody has read it yet.
  final DateTime? burnAt;

  /// Creates a message. [clientId] defaults to '' when not supplied; pass one
  /// explicitly for optimistic local sends.
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.kind = 'text',
    required this.createdAt,
    this.checkId = 0,
    this.replyToId,
    this.replyToName,
    this.replyToContent,
    this.editedAt,
    this.deletedAt,
    this.senderName,
    this.senderAvatar,
    this.senderVerified = false,
    this.senderIsBot = false,
    this.senderMemberLevel = 0,
    this.senderMemberActive = false,
    this.senderNameColor = '',
    this.senderNameColorTo = '',
    this.senderNameDynamic = false,
    this.senderNameColors = const [],
    this.senderNameGradientDirection = '',
    this.senderAvatarFrame = '',
    this.attachments = const [],
    this.mentions = const [],
    String? clientId,
    this.status = MessageStatus.sent,
    this.decryptedContent,
    this.uploadProgress,
    this.burnSeconds = 0,
    this.burnAt,
  }) : clientId = clientId ?? '';

  /// The sentinel user id stored in [mentions] for an @everyone mention.
  static const int everyoneSentinel = -1;

  /// True when this message mentions the current user (or everyone).
  bool mentionsMe(int myUserId) =>
      mentions.contains(myUserId) || mentions.contains(everyoneSentinel);

  /// The text to display: the decrypted plaintext for E2EE messages, otherwise
  /// the raw content. Undecryptable E2EE envelopes are masked so the raw
  /// ciphertext never leaks into the UI.
  String get displayContent {
    if (decryptedContent != null) return decryptedContent!;
    return isEnvelope ? '' : content;
  }

  /// True when [content] looks like an E2EE envelope (a JSON object carrying
  /// the version/sender/index/nonce/cipher fields). Used to avoid rendering
  /// ciphertext when a message could not be decrypted.
  bool get isEnvelope {
    final t = content.trimLeft();
    if (!t.startsWith('{')) return false;
    final decoded = _tryDecodeJson(t);
    return decoded is Map<String, dynamic> &&
        decoded.containsKey('v') &&
        decoded.containsKey('c');
  }

  /// True when this is a text message from an encrypted conversation that has
  /// not been decrypted yet.
  bool get needsDecryption => decryptedContent == null && !isSystem;

  /// True when this message was soft-deleted ([deletedAt] set).
  bool get isDeleted => deletedAt != null;
  /// True when this message was edited after it was sent.
  bool get isEdited => editedAt != null;
  /// True for server-generated system events (kind starts with 'system.').
  bool get isSystem => kind.startsWith('system.');
  /// True when this message carries a check (red packet) with a valid id.
  bool get isCheck => kind == 'check' && checkId > 0;
  /// True for 'system.join' events.
  bool get isJoin => kind == 'system.join';
  /// True for 'system.leave' events.
  bool get isLeave => kind == 'system.leave';
  /// True while the message has no server-assigned id yet.
  bool get isLocal => id <= 0;
  /// True while the optimistic send is still uploading/sending.
  bool get isPending => status == MessageStatus.sending;
  /// True when the optimistic send failed.
  bool get isFailed => status == MessageStatus.failed;

  /// True when this message is armed for burn-after-read and not yet deleted.
  bool get isBurn => burnSeconds > 0 && !isDeleted;

  /// True once a recipient has read the message and the countdown deadline is
  /// known (burnAt set) but not yet reached.
  bool get burnArmed => isBurn && burnAt != null;

  /// Whole seconds left before this message burns, or null while the deadline
  /// is unknown. Never negative.
  int? secondsToBurn(DateTime now) {
    if (!burnArmed) return null;
    final left = burnAt!.difference(now).inSeconds;
    return left < 0 ? 0 : left;
  }

  /// Sender's display name for the message bubble, or 'Unknown' when absent.
  String get displayName => senderName ?? 'Unknown';

  /// Stable ordering key: newest timestamp wins; ties broken by id so locally
  /// created messages sort by creation time, not by insertion.
  int compareForOrder(ChatMessage other) {
    final c = other.createdAt.compareTo(createdAt);
    if (c != 0) return c;
    return other.id.compareTo(id);
  }

  /// Copy with a new status / server fields (used when an optimistic send
  /// resolves).
  ChatMessage resolve({int? serverId, MessageStatus? status}) {
    return ChatMessage(
      id: serverId ?? id,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      kind: kind,
      replyToId: replyToId,
      replyToName: replyToName,
      replyToContent: replyToContent,
      editedAt: editedAt,
      deletedAt: deletedAt,
      createdAt: createdAt,
      senderName: senderName,
      senderAvatar: senderAvatar,
      senderVerified: senderVerified,
      senderIsBot: senderIsBot,
      senderMemberLevel: senderMemberLevel,
      senderMemberActive: senderMemberActive,
      senderNameColor: senderNameColor,
      senderNameColorTo: senderNameColorTo,
      senderNameDynamic: senderNameDynamic,
      senderNameColors: senderNameColors,
      senderNameGradientDirection: senderNameGradientDirection,
      senderAvatarFrame: senderAvatarFrame,
      attachments: attachments,
      mentions: mentions,
      clientId: clientId,
      status: status ?? MessageStatus.sent,
      decryptedContent: decryptedContent,
      burnSeconds: burnSeconds,
      burnAt: burnAt,
    );
  }

  /// Sentinel distinguishing "not passed" from an explicit null reset.
  static const Object _unset = Object();

  /// Copies this message, overriding only the given fields and preserving
  /// everything else (member styling, reply metadata, attachments, ...).
  /// Used to stamp send status or decrypted plaintext without losing fields.
  ChatMessage copyWith({
    int? id,
    String? content,
    String? kind,
    int? replyToId,
    String? replyToName,
    String? replyToContent,
    DateTime? editedAt,
    DateTime? deletedAt,
    DateTime? createdAt,
    String? senderName,
    String? senderAvatar,
    bool? senderVerified,
    bool? senderIsBot,
    int? senderMemberLevel,
    bool? senderMemberActive,
    String? senderNameColor,
    String? senderNameColorTo,
    bool? senderNameDynamic,
    List<String>? senderNameColors,
    String? senderNameGradientDirection,
    String? senderAvatarFrame,
    List<Attachment>? attachments,
    List<int>? mentions,
    String? clientId,
    MessageStatus? status,
    int? burnSeconds,
    Object? burnAt = _unset,
    Object? decryptedContent = _unset,
    Object? uploadProgress = _unset,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      content: content ?? this.content,
      kind: kind ?? this.kind,
      replyToId: replyToId ?? this.replyToId,
      replyToName: replyToName ?? this.replyToName,
      replyToContent: replyToContent ?? this.replyToContent,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      senderVerified: senderVerified ?? this.senderVerified,
      senderIsBot: senderIsBot ?? this.senderIsBot,
      senderMemberLevel: senderMemberLevel ?? this.senderMemberLevel,
      senderMemberActive: senderMemberActive ?? this.senderMemberActive,
      senderNameColor: senderNameColor ?? this.senderNameColor,
      senderNameColorTo: senderNameColorTo ?? this.senderNameColorTo,
      senderNameDynamic: senderNameDynamic ?? this.senderNameDynamic,
      senderNameColors: senderNameColors ?? this.senderNameColors,
      senderNameGradientDirection:
          senderNameGradientDirection ?? this.senderNameGradientDirection,
      senderAvatarFrame: senderAvatarFrame ?? this.senderAvatarFrame,
      attachments: attachments ?? this.attachments,
      mentions: mentions ?? this.mentions,
      clientId: clientId ?? this.clientId,
      status: status ?? this.status,
      burnSeconds: burnSeconds ?? this.burnSeconds,
      burnAt: identical(burnAt, _unset) ? this.burnAt : burnAt as DateTime?,
      decryptedContent: identical(decryptedContent, _unset)
          ? this.decryptedContent
          : decryptedContent as String?,
      uploadProgress: identical(uploadProgress, _unset)
          ? this.uploadProgress
          : uploadProgress as double?,
    );
  }

  /// Deserializes from the server's message payload. Does not populate
  /// client-side fields ([clientId], [status], [decryptedContent],
  /// [uploadProgress]); those are set locally after construction.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    List<Attachment> attachments = const [];
    if (rawAttachments is List) {
      attachments = rawAttachments
          .whereType<Map<String, dynamic>>()
          .map((a) => Attachment.fromJson(a))
          .toList();
    }
    return ChatMessage(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversation_id']),
      senderId: _asInt(json['sender_id']),
      content: json['content'] as String? ?? '',
      kind: json['kind'] as String? ?? 'text',
      checkId: _asInt(json['check_id']),
      replyToId: json['reply_to_id'] is num ? (json['reply_to_id'] as num).toInt() : null,
      replyToName: json['reply_to_name'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      editedAt: _asDate(json['edited_at']),
      deletedAt: _asDate(json['deleted_at']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      senderName: json['sender_name'] as String?,
      senderAvatar: json['sender_avatar'] as String?,
      senderVerified: json['sender_verified'] as bool? ?? false,
      senderIsBot: json['sender_is_bot'] as bool? ?? false,
      senderMemberLevel: _asInt(json['sender_member_level']),
      senderMemberActive: json['sender_member_active'] as bool? ?? false,
      senderNameColor: json['sender_name_color'] as String? ?? '',
      senderNameColorTo: json['sender_name_color_to'] as String? ?? '',
      senderNameDynamic: json['sender_name_dynamic'] as bool? ?? false,
      senderNameColors: _asStringList(json['sender_name_colors']),
      senderNameGradientDirection: json['sender_name_gradient_direction'] as String? ?? '',
      senderAvatarFrame: json['sender_avatar_frame'] as String? ?? '',
      attachments: attachments,
      mentions: _asIntList(json['mentions']),
      burnSeconds: _asInt(json['burn_seconds']),
      burnAt: _asDate(json['burn_at']),
    );
  }

  /// Coerces a mentions array, tolerating strings and missing values.
  static List<int> _asIntList(Object? value) {
    if (value is List) {
      return value
          .map((e) {
            if (e is int) return e;
            if (e is num) return e.toInt();
            if (e is String) return int.tryParse(e);
            return null;
          })
          .whereType<int>()
          .toList();
    }
    return const [];
  }

  /// Safely coerces an id field, tolerating strings and missing values so a
  /// schema change on the server never crashes the client.
  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  static DateTime? _asDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  static Object? _tryDecodeJson(String input) {
    try {
      return jsonDecode(input);
    } catch (_) {
      return null;
    }
  }
}

/// Generates a unique client-side message id. Uses a timestamp + random suffix
/// so it is monotonic within a session and unique across devices.
String generateClientId() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '$ts-$rand';
}
