import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/story.dart';

/// Saves and loads the user's stories locally on the device.
///
/// Simple JSON list in [SharedPreferences] — good enough for the MVP. Can be
/// upgraded to cloud sync later without changing callers.
class StoryStore {
  static const _key = 'creative_aac.stories.v1';

  Future<List<Story>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    final stories = list
        .map((e) => Story.fromJson(e as Map<String, dynamic>))
        .toList();
    // Newest first.
    stories.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return stories;
  }

  Future<void> save(Story story) async {
    final all = await loadAll();
    all.removeWhere((s) => s.id == story.id);
    all.add(story);
    await _write(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((s) => s.id == id);
    await _write(all);
  }

  Future<void> _write(List<Story> stories) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(stories.map((s) => s.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}
