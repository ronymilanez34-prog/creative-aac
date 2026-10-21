import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/board.dart';
import 'image_sink.dart';
import 'obz_importer.dart';

/// Web variant of the board store: no filesystem, so imported images are
/// kept as data URIs in browser storage (up to a size budget). The friend
/// must see THEIR pictures on the web too — familiarity is the whole point,
/// and a placeholder bubble is nobody's picture.
class BoardStore {
  static const _key = 'creative_aac.board_words.v1';
  static const _layoutKey = 'creative_aac.board_layout.v1';
  static const _imagesKey = 'creative_aac.board_images.v1';

  Future<List<BoardWord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    Map<String, dynamic> imageUris = const {};
    final rawImages = prefs.getString(_imagesKey);
    if (rawImages != null && rawImages.isNotEmpty) {
      try {
        imageUris = jsonDecode(rawImages) as Map<String, dynamic>;
      } catch (_) {}
    }
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        BoardWord.fromJson(e)
            .withImagePath(imageUris[e['imageFile']]?.toString()),
    ];
  }

  /// The board's map with pictures as data URIs (see [load]); null when
  /// nothing was imported.
  Future<BoardLayout?> loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_layoutKey);
    if (raw == null || raw.isEmpty) return null;
    final BoardLayout layout;
    try {
      layout = BoardLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
    final uris = await _imageUris();
    return layout.withImagePaths(
        (file) => file == null ? null : uris[file]?.toString());
  }

  Future<Map<String, dynamic>> _imageUris() async {
    final prefs = await SharedPreferences.getInstance();
    final rawImages = prefs.getString(_imagesKey);
    if (rawImages == null || rawImages.isEmpty) return const {};
    try {
      return jsonDecode(rawImages) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  Future<ObzImportResult> importFromBytes(Uint8List bytes) async {
    final sink = MemoryImageSink();
    final result = await ObzImporter().import(bytes: bytes, images: sink);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(result.words.map((w) => w.toJson()).toList()),
    );
    final layout = result.layout;
    if (layout == null) {
      await prefs.remove(_layoutKey);
    } else {
      await prefs.setString(_layoutKey, jsonEncode(layout.toJson()));
    }
    final uris = <String, String>{
      for (final e in sink.images.entries)
        e.key: 'data:${_mime(e.key)};base64,${base64Encode(e.value)}',
    };
    try {
      await prefs.setString(_imagesKey, jsonEncode(uris));
    } catch (_) {
      // Browser storage full — keep the words, drop the pictures.
      await prefs.remove(_imagesKey);
    }
    return result;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_layoutKey);
    await prefs.remove(_imagesKey);
  }

  String _mime(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/png';
    }
  }
}
