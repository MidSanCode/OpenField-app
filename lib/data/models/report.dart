/// The kinds of content a report can point at. The values are the exact
/// `target_type` strings the server accepts.
class ReportTarget {
  /// A post in the square or in a camp.
  static const String post = 'post';

  /// A single chat message.
  static const String message = 'message';

  /// Another user's account.
  static const String user = 'user';
}

/// Lifecycle of a report, matching the server's `reports.status` values.
class ReportStatus {
  /// Filed and not yet looked at by an operator.
  static const String pending = 'pending';

  /// An operator confirmed it (the acted-upon content may already be gone).
  static const String reviewed = 'reviewed';

  /// An operator decided no action was warranted.
  static const String dismissed = 'dismissed';
}

/// A moderation report the signed-in user filed against a post, a chat
/// message or another user. Reviewing happens in the admin panel; the client
/// only files reports and shows the caller their own history.
class Report {
  /// Server-assigned report id.
  final int id;

  /// User id of the reporter (the caller for [ApiService.listMyReports]).
  final int reporterId;

  /// Reporter's display name ('' when the payload omits it).
  final String reporterName;

  /// What was reported: one of the [ReportTarget] values, or '' when the
  /// server sent an unknown kind (forward compatibility).
  final String targetType;

  /// Id of the reported row in its own table.
  final int targetId;

  /// The reporter's explanation.
  final String reason;

  /// One of the [ReportStatus] values.
  final String status;

  /// Display name of the operator who resolved it ('' while pending).
  final String reviewerUsername;

  /// Optional note the operator left when resolving ('' while pending).
  final String reviewNote;

  /// When the report was filed (server timestamp).
  final DateTime createdAt;

  /// When it was resolved, or null while it is still pending.
  final DateTime? reviewedAt;

  /// Creates a report; see [fromJson] for payload defaults.
  Report({
    required this.id,
    required this.reporterId,
    this.reporterName = '',
    required this.targetType,
    required this.targetId,
    this.reason = '',
    this.status = ReportStatus.pending,
    this.reviewerUsername = '',
    this.reviewNote = '',
    required this.createdAt,
    this.reviewedAt,
  });

  /// Deserializes from the server's report payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: _asInt(json['id']),
      reporterId: _asInt(json['reporter_id']),
      reporterName: json['reporter_name'] as String? ?? '',
      targetType: json['target_type'] as String? ?? '',
      targetId: _asInt(json['target_id']),
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String? ?? ReportStatus.pending,
      reviewerUsername: json['reviewer_username'] as String? ?? '',
      reviewNote: json['review_note'] as String? ?? '',
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      reviewedAt: _asDate(json['reviewed_at']),
    );
  }

  /// The report is still waiting for an operator.
  bool get isPending => status == ReportStatus.pending;

  /// The operator confirmed the report.
  bool get isReviewed => status == ReportStatus.reviewed;

  /// The operator dismissed the report.
  bool get isDismissed => status == ReportStatus.dismissed;

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
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
}
