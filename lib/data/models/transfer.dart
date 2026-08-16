/// A pending or settled user-to-user currency transfer.
class Transfer {
  final int id;
  final int senderId;
  final int recipientId;
  final double amount;
  final String status;
  final String note;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final DateTime? refundedAt;
  final String senderName;
  final String senderUsername;
  final String senderAvatar;
  final String recipientName;
  final String recipientUsername;
  final String recipientAvatar;

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

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
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