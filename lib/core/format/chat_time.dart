String _two(int n) => n.toString().padLeft(2, '0');

/// Formats a chat timestamp with calendar context:
///
/// - today: `12:04`
/// - yesterday: `Yesterday 12:04` (via [yesterdayLabel])
/// - this year: `8/12 12:04`
/// - earlier years: `2025/8/12 12:04`
///
/// [toLocal] converts a server UTC timestamp into the display timezone (see
/// [SettingsService.displayTime]).
String formatChatTime(
  DateTime utc,
  DateTime Function(DateTime) toLocal,
  String yesterdayLabel,
) {
  final local = toLocal(utc);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final hm = '${_two(local.hour)}:${_two(local.minute)}';

  if (day == today) return hm;
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (day == yesterday) return '$yesterdayLabel $hm';
  if (local.year == now.year) return '${local.month}/${local.day} $hm';
  return '${local.year}/${local.month}/${local.day} $hm';
}