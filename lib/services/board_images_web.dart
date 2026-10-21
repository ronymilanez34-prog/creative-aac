import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';

/// Where the web keeps the imported board's pictures: IndexedDB.
///
/// Until 21.10 they were data URIs inside localStorage, next to everything
/// else (stories with their pictures, the log, the profile). Safari gives
/// an origin about 5MB there in total; a real board (121 pictures, 1.1MB
/// of JPEG, 1.5MB as base64) pushed past it and the fallback dropped EVERY
/// picture, silently — the board came up as text only on the iPad.
/// IndexedDB holds hundreds of MB and stores bytes as bytes.
///
/// One record per picture, keyed by its file name (the same name the
/// layout and the word list carry). A factory can be injected for tests.
class BoardImagesWeb {
  BoardImagesWeb({IdbFactory? factory}) : _factory = factory ?? idbFactoryBrowser;

  static const _db = 'creative_aac';
  static const _store = 'board_images';

  final IdbFactory _factory;

  Future<Database> _open() => _factory.open(
        _db,
        version: 1,
        onUpgradeNeeded: (e) {
          final db = e.database;
          if (!db.objectStoreNames.contains(_store)) {
            db.createObjectStore(_store);
          }
        },
      );

  /// Replaces every stored picture with [images]. Returns how many were
  /// written — the caller tells the person when it is fewer than imported.
  Future<int> replaceAll(Map<String, Uint8List> images) async {
    final db = await _open();
    try {
      final txn = db.transaction(_store, idbModeReadWrite);
      final store = txn.objectStore(_store);
      await store.clear();
      var written = 0;
      for (final e in images.entries) {
        await store.put(e.value, e.key);
        written++;
      }
      await txn.completed;
      return written;
    } finally {
      db.close();
    }
  }

  /// Every stored picture as a data URI, by file name.
  Future<Map<String, String>> loadDataUris() async {
    final db = await _open();
    try {
      final txn = db.transaction(_store, idbModeReadOnly);
      final store = txn.objectStore(_store);
      final out = <String, String>{};
      final cursors = store.openCursor(autoAdvance: true);
      await for (final c in cursors) {
        final key = c.key.toString();
        final value = c.value;
        final bytes = value is Uint8List
            ? value
            : value is List<int>
                ? Uint8List.fromList(value)
                : null;
        if (bytes != null) out[key] = dataUri(key, bytes);
      }
      await txn.completed;
      return out;
    } finally {
      db.close();
    }
  }

  Future<void> clear() async {
    final db = await _open();
    try {
      final txn = db.transaction(_store, idbModeReadWrite);
      await txn.objectStore(_store).clear();
      await txn.completed;
    } finally {
      db.close();
    }
  }

  static String dataUri(String name, Uint8List bytes) =>
      'data:${mimeFor(name)};base64,${base64Encode(bytes)}';

  static String mimeFor(String name) {
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
