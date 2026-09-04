import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/board.dart';
import 'image_sink_io.dart';
import 'obz_importer.dart';

/// Saves and loads the user's imported vocabulary (their own board words and
/// images) locally on the device.
///
/// Word list lives in [SharedPreferences] as JSON (same pattern as
/// [StoryStore]); the images live as files in the app documents directory,
/// referenced by relative name because the directory's absolute path can
/// change between launches on iOS.
class BoardStore {
  static const _key = 'creative_aac.board_words.v1';
  static const _imagesDirName = 'board_images';

  /// Loads the imported words, with [BoardWord.imagePath] resolved to
  /// absolute paths. Empty list when nothing was imported yet.
  Future<List<BoardWord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final dir = await _imagesDir();
    final list = jsonDecode(raw) as List;
    return list.map((e) {
      final w = BoardWord.fromJson(e as Map<String, dynamic>);
      if (w.imageFile == null) return w;
      final path = '${dir.path}/${w.imageFile}';
      return w.withImagePath(File(path).existsSync() ? path : null);
    }).toList();
  }

  /// Imports an .obz/.obf file, replacing any previously imported board.
  /// Extraction happens into a scratch directory first, so a bad file never
  /// destroys an existing import.
  Future<ObzImportResult> importFromBytes(Uint8List bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final scratch = Directory('${docs.path}/${_imagesDirName}_new');
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    scratch.createSync(recursive: true);

    final ObzImportResult result;
    try {
      result = await ObzImporter()
          .import(bytes: bytes, images: DirectoryImageSink(scratch));
    } catch (_) {
      scratch.deleteSync(recursive: true);
      rethrow;
    }

    final live = Directory('${docs.path}/$_imagesDirName');
    if (live.existsSync()) live.deleteSync(recursive: true);
    scratch.renameSync(live.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(result.words.map((w) => w.toJson()).toList()),
    );

    // Resolve image paths against the final directory.
    final words = result.words
        .map((w) => w.imageFile == null
            ? w
            : w.withImagePath('${live.path}/${w.imageFile}'))
        .toList();
    return ObzImportResult(
      words: words,
      boardsCount: result.boardsCount,
      imagesCount: result.imagesCount,
    );
  }

  /// Removes the imported board entirely (words and image files).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    final dir = await _imagesDir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  Future<Directory> _imagesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$_imagesDirName');
  }
}
