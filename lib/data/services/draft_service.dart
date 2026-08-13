import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single saved post draft.
class PostDraft {
  final String id;
  final String content;
  final List<String> images;
  final DateTime updatedAt;

  const PostDraft({
    required this.id,
    required this.content,
    required this.images,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'images': images,
        'updatedAt': updatedAt.toIso8601String(),
      };

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

  Future<void> delete(String id) async {
    final all = await list()..removeWhere((d) => d.id == id);
    await _store(all);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _store(List<PostDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }
}