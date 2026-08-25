import 'package:flutter/foundation.dart';

/// Lightweight in-memory cache for the total number of unread chat messages
/// across all conversations. The chat list updates this whenever it loads /
/// reloads the conversation list, and the app shell reads it to render the
/// red dot badge on the bottom navigation.
class ChatUnreadService extends ChangeNotifier {
  int _totalUnread = 0;

  int get totalUnread => _totalUnread;

  /// True when there's at least one unread message waiting for the user.
  bool get hasUnread => _totalUnread > 0;

  /// Sets the latest total. Callers should debounce / coalesce to avoid
  /// notifying every push event.
  void setTotal(int total) {
    if (total == _totalUnread) return;
    _totalUnread = total < 0 ? 0 : total;
    notifyListeners();
  }

  /// Resets the badge after the user explicitly marked everything as read.
  void clear() {
    if (_totalUnread == 0) return;
    _totalUnread = 0;
    notifyListeners();
  }
}
