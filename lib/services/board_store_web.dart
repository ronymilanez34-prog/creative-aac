import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/board.dart';
import 'board_images_web.dart';
import 'image_sink.dart';
import 'obz_importer.dart';

/// Web variant of the board store: words and layout in browser storage,
/// the pictures in IndexedDB ([BoardImagesWeb]) and handed out as data
/// URIs. The friend must see THEIR pictures on the web too — familiarity
/// is the whole point, and a placeholder bubble is nobody's picture.
///
/// Before 21.10 the pictures lived as data URIs in localStorage; a real
/// board overflowed Safari's quota and every picture was dropped, silently.
/// Now the store is bigger, and a picture that still could not be kept is
/// counted and said out loud ([ObzImportResult.imagesDropped]).
class BoardStore {
  BoardStore({IdbFactory? idbFactory})
      : _images = BoardImagesWeb(factory: idbFactory);

  static const _key = 'creative_aac.board_words.v1';
  static const _layoutKey = 'creative_aac.board_layout.v1';

  /// Where the pictures used to live (data URIs in localStorage). Still
  /// read when IndexedDB has nothing, so an import made before 21.10
  /// keeps its pictures; removed on the next import.
  static const _legacyImagesKey = 'creative_aac.board_images.v1';

  final BoardImagesWeb _images;

  Future<List<BoardWord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final imageUris = await _imageUris();
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        BoardWord.fromJson(e).withImagePath(imageUris[e['imageFile']]),
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
    return layout.withImagePaths((file) => file == null ? null : uris[file]);
  }

  Future<Map<String, String>> _imageUris() async {
    try {
      final stored = await _images.loadDataUris();
      if (stored.isNotEmpty) return stored;
    } catch (_) {
      // IndexedDB unavailable (private mode, old browser) — try the old place.
    }
    final prefs = await SharedPreferences.getInstance();
    final rawImages = prefs.getString(_legacyImagesKey);
    if (rawImages == null || rawImages.isEmpty) return const {};
    try {
      final m = jsonDecode(rawImages) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: e.value.toString()};
    } catch (_) {
      return const {};
    }
  }

  Future<ObzImportResult> importFromBytes(Uint8List bytes) async {
    // IndexedDB has room for a whole board set; the budget only guards
    // against a runaway package.
    final sink = MemoryImageSink(budgetBytes: 40 * 1000 * 1000);
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
    await prefs.remove(_legacyImagesKey);

    var written = 0;
    try {
      written = await _images.replaceAll(sink.images);
    } catch (_) {
      // Storage refused — the words and the map stay; the pictures are
      // reported as lost rather than vanishing.
      written = 0;
    }
    final dropped = sink.dropped + (sink.images.length - written);
    // Hand back the pictures resolved, like the device store does: the
    // import screen shows the result at once, and until 21.10 it showed
    // bubbles until the screen was reopened ("nothing changed").
    final uris = {
      for (final e in sink.images.entries)
        e.key: BoardImagesWeb.dataUri(e.key, e.value),
    };
    return ObzImportResult(
      words: [
        for (final w in result.words) w.withImagePath(uris[w.imageFile]),
      ],
      boardsCount: result.boardsCount,
      unreachableBoards: result.unreachableBoards,
      imagesCount: result.imagesCount,
      imagesDropped: dropped,
      layout: layout?.withImagePaths((f) => f == null ? null : uris[f]),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_layoutKey);
    await prefs.remove(_legacyImagesKey);
    try {
      await _images.clear();
    } catch (_) {}
  }
}
