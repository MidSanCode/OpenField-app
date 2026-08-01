import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists an in-progress post draft (text + selected image paths).
class DraftService {
  static const _key = 'post_draft';

  Future<({String content, List<String> images})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final images = (data['images'] as List? ?? const [])
          .whereType<String>()
          .toList();
      return (content: data['content'] as String? ?? '', images: images);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String content, List<String> images) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'content': content, 'images': images}),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<bool> hasDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }
}
