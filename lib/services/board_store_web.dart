import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/board.dart';
import 'image_sink.dart';
import 'obz_importer.dart';

/// Web variant of the board store: no filesystem, so imports keep the words
/// (labels + spoken text) and skip the images. The full experience lives on
/// the installed app; the web build stays functional instead of failing to
/// compile on dart:io.
class BoardStore {
  static const _key = 'creative_aac.board_words.v1';

  Future<List<BoardWord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => BoardWord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ObzImportResult> importFromBytes(Uint8List bytes) async {
    final result = await ObzImporter()
        .import(bytes: bytes, images: const NoopImageSink());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(result.words.map((w) => w.toJson()).toList()),
    );
    return result;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
