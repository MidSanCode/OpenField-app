/// A pending or settled user-to-user currency transfer.
class Transfer {
  /// Server-assigned transfer id.
  final int id;
  /// User id of the sender.
  final int senderId;
  /// User id of the recipient.
  final int recipientId;
  /// Amount transferred, in coins.
  final double amount;
  /// Lifecycle state: 'pending', 'accepted', 'declined' or 'refunded'.
  final String status;
  /// Free-form note the sender attached ('' when none).
  final String note;
  /// When the transfer was created (localized timestamp).
  final DateTime createdAt;
  /// When the recipient accepted or declined; null while pending.
  final DateTime? decidedAt;
  /// When the transfer was refunded; null until a refund happens.
  final DateTime? refundedAt;
  /// Sender's display name ('' when the payload omits it).
  final String senderName;
  /// Sender's @username ('' when the payload omits it).
  final String senderUsername;
  /// Sender's avatar URL ('' when the payload omits it).
  final String senderAvatar;
  /// Recipient's display name ('' when the payload omits it).
  final String recipientName;
  /// Recipient's @username ('' when the payload omits it).
  final String recipientUsername;
  /// Recipient's avatar URL ('' when the payload omits it).
  final String recipientAvatar;

  /// Creates a transfer; see [fromJson] for payload defaults.
  const Transfer({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.amount,
    required this.status,
    required this.note,
    required this.createdAt,
    this.decidedAt,
    this.refundedAt,
    this.senderName = '',
    this.senderUsername = '',
    this.senderAvatar = '',
    this.recipientName = '',
    this.recipientUsername = '',
    this.recipientAvatar = '',
  });

  /// Deserializes from the server's transfer payload, tolerating missing or
  /// mistyped fields (defaults apply per field; unparseable creation dates
  /// fall back to the Unix epoch).
  factory Transfer.fromJson(Map<String, dynamic> json) {
    return Transfer(
      id: _asInt(json['id']),
      senderId: _asInt(json['sender_id']),
      recipientId: _asInt(json['recipient_id']),
      amount: _asDouble(json['amount']),
      status: json['status'] as String? ?? 'pending',
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      decidedAt: _asDate(json['decided_at']),
      refundedAt: _asDate(json['refunded_at']),
      senderName: json['sender_name'] as String? ?? '',
      senderUsername: json['sender_username'] as String? ?? '',
      senderAvatar: json['sender_avatar'] as String? ?? '',
      recipientName: json['recipient_name'] as String? ?? '',
      recipientUsername: json['recipient_username'] as String? ?? '',
      recipientAvatar: json['recipient_avatar'] as String? ?? '',
    );
  }

  /// True while waiting for the recipient to accept or decline.
  bool get isPending => status == 'pending';
  /// True when the recipient accepted the transfer.
  bool get isAccepted => status == 'accepted';
  /// True when the recipient declined the transfer.
  bool get isDeclined => status == 'declined';
  /// True when the transfer was refunded to the sender.
  bool get isRefunded => status == 'refunded';

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _asDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }
}