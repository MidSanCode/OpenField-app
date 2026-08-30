import 'dart:convert';
import 'dart:math';
import 'attachment.dart';

/// How a message relates to the server. [sent] is confirmed; [sending] and
/// [failed] are local-only states for optimistic UI.
enum MessageStatus { sending, sent, failed }

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String content;

  /// Server-side message kind: 'text' or system kinds such as
  /// 'system.join' / 'system.leave' / 'system.mute' / 'system.unmute' /
  /// 'system.mute.all' / 'system.unmute.all'.
  final String kind;
  final int? replyToId;
  final String? replyToName;
  final String? replyToContent;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime createdAt;

  /// For kind == 'check' messages: the id of the attached check. Fetch the
  /// full check (amount, claims, status) from /checks/:id before rendering.
  final int checkId;
  final String? senderName;
  final String? senderAvatar;
  final bool senderVerified;
  final bool senderIsBot;
  final int senderMemberLevel;
  final bool senderMemberActive;
  final String senderNameColor;
  final String senderNameColorTo;
  final bool senderNameDynamic;
  final List<String> senderNameColors;
  final String senderNameGradientDirection;
  final String senderAvatarFrame;
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

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
  bool get isSystem => kind.startsWith('system.');
  bool get isCheck => kind == 'check' && checkId > 0;
  bool get isJoin => kind == 'system.join';
  bool get isLeave => kind == 'system.leave';
  bool get isLocal => id <= 0;
  bool get isPending => status == MessageStatus.sending;
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
