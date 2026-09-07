import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single saved post draft.
class PostDraft {
  /// Stable identifier; caller-chosen (usually a timestamp string).
  final String id;
  /// Draft body text.
  final String content;
  /// Local file paths of images attached to the draft.
  final List<String> images;
  /// When the draft was last saved.
  final DateTime updatedAt;

  /// Creates a draft; all fields are required and immutable afterwards.
  const PostDraft({
    required this.id,
    required this.content,
    required this.images,
    required this.updatedAt,
  });

  /// Serializes to a JSON map ([updatedAt] as an ISO-8601 string).
  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'images': images,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Parses a stored JSON map, falling back to safe defaults for missing or
  /// malformed fields (a fresh timestamp id, empty content/images, now) so a
  /// corrupt entry never throws.
  factory PostDraft.fromJson(Map<String, dynamic> json) => PostDraft(
        id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        content: json['content'] as String? ?? '',
        images: (json['images'] as List? ?? const []).whereType<String>().toList(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Persists multiple in-progress post drafts (text + selected image paths).
class DraftService {
  static const _key = 'post_drafts';

  /// Loads all saved drafts, oldest insertion first. Returns an empty list
  /// when nothing is stored or the blob fails to parse; never throws.
  Future<List<PostDraft>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(PostDraft.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the draft with [id], or null when no such draft exists.
  Future<PostDraft?> get(String id) async {
    for (final draft in await list()) {
      if (draft.id == id) return draft;
    }
    return null;
  }

  /// Upserts a draft: existing drafts with the same [id] are replaced.
  Future<void> save(PostDraft draft) async {
    final all = await list();
    final index = all.indexWhere((d) => d.id == draft.id);
    if (index >= 0) {
      all[index] = draft;
    } else {
      all.add(draft);
    }
    await _store(all);
  }

  /// Removes the draft with [id]; a no-op when it does not exist.
  Future<void> delete(String id) async {
    final all = await list()..removeWhere((d) => d.id == id);
    await _store(all);
  }

  /// Deletes every draft by removing the storage key entirely.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _store(List<PostDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }
}