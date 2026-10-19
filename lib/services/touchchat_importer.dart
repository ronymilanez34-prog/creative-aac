import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/board.dart';
import 'image_sink.dart';
import 'obz_importer.dart';
import 'sqlite_reader.dart';

/// Imports a TouchChat board (Saltillo/PRC) — the app everyone at the
/// village uses — straight from its own export, on the device.
///
/// What TouchChat writes (seen in a real Hebrew TouchChat HD backup,
/// 19.10.2026):
///  • `.ce` — a zip holding `<name>.c4v` (the board, a SQLite database),
///    `Images.c4s` (custom pictures, SQLite), `Manifest.c4i`, `version.txt`.
///  • `.c4v` — the board database on its own.
/// In the board: `buttons` (label, message = what is spoken, visible,
/// symbol_link_id), `actions` (what a button does, by numeric code),
/// `pages` → `button_box_instances` → `button_box_cells` (where each button
/// sits), `special_pages` (HOME), `variables` (board name, locale).
///
/// Kept: every visible button with a label, spoken text included (TouchChat
/// often stores it WITH nikud — good for the Hebrew voice). Dropped: system
/// buttons — delete (action 28) and keyboard (61/71), seen on that board.
/// Order: the home page first, then the other pages, each top-to-bottom —
/// the words a friend reaches first come first.
///
/// Pictures: TouchChat's built-in symbols (SymbolStix) are licensed and are
/// NOT inside the export, so most words arrive without a picture. Custom
/// pictures (photos added on the device) live in Images.c4s; when one is a
/// plain PNG/JPEG/GIF it is kept. That path was not seen with real data yet.
class TouchChatImporter {
  static const _systemActions = {28, 61, 71};
  static const _systemLabels = {'מקלדת', 'מחיקה', 'keyboard', 'delete', 'clear'};

  /// True when [bytes] look like a TouchChat board: a zip with a `.c4v`
  /// inside, or a SQLite database with TouchChat's tables.
  static bool looks(Uint8List bytes, {Archive? archive}) {
    if (archive != null) {
      return archive.files.any((f) => f.isFile && f.name.toLowerCase().endsWith('.c4v'));
    }
    if (!SqliteReader.isSqlite(bytes)) return false;
    try {
      final db = SqliteReader(bytes);
      return db.hasTable('buttons') && db.hasTable('button_box_cells');
    } catch (_) {
      return false;
    }
  }

  Future<ObzImportResult> import({
    required Uint8List bytes,
    required ImageSink images,
    Archive? archive,
  }) async {
    Uint8List board;
    Uint8List? imageDb;
    if (archive != null) {
      final c4v = archive.files.firstWhere(
        (f) => f.isFile && f.name.toLowerCase().endsWith('.c4v'),
      );
      board = Uint8List.fromList(c4v.content as List<int>);
      for (final f in archive.files) {
        if (f.isFile && f.name.toLowerCase().endsWith('.c4s')) {
          imageDb = Uint8List.fromList(f.content as List<int>);
        }
      }
    } else {
      board = bytes;
    }

    final SqliteReader db;
    try {
      db = SqliteReader(board);
    } on SqliteFormatException {
      throw const ObzFormatException('קובץ ה-TouchChat לא נפתח — נסו לייצא אותו שוב');
    }
    if (!db.hasTable('buttons')) {
      throw const ObzFormatException('לא נמצאו כפתורים בלוח ה-TouchChat');
    }

    final pictures = _pictures(imageDb);
    final symbolRid = <int, String>{
      if (db.hasTable('symbol_links'))
        for (final r in db.rows('symbol_links'))
          if (r['id'] is int && r['rid'] != null) r['id'] as int: '${r['rid']}',
    };

    // resource_id → action codes (a button may carry several).
    final actions = <int, Set<int>>{};
    if (db.hasTable('actions')) {
      for (final a in db.rows('actions')) {
        final res = a['resource_id'];
        final code = a['code'];
        if (res is int && code is int) (actions[res] ??= {}).add(code);
      }
    }

    final ordered = _orderedButtons(db);
    final words = <BoardWord>[];
    final seen = <String>{};
    var imagesWritten = 0;
    for (final b in ordered) {
      if (words.length >= ObzImporter.maxWords) break;
      if (b['visible'] == 0) continue;
      final label = (b['label'] ?? '').toString().trim();
      if (label.isEmpty) continue;
      if (_systemLabels.contains(label.toLowerCase())) continue;
      final res = b['resource_id'];
      if (res is int && (actions[res] ?? const {}).any(_systemActions.contains)) {
        continue;
      }
      if (!seen.add(_plain(label).toLowerCase())) continue;

      final message = (b['message'] ?? '').toString().trim();
      String? imageFile;
      final link = b['symbol_link_id'];
      final rid = link is int ? symbolRid[link] : null;
      final pic = rid == null ? null : pictures[rid];
      if (pic != null) {
        imageFile = images.write('img_${imagesWritten++}.${pic.ext}', pic.data);
      }
      words.add(BoardWord(
        id: 'w${words.length}',
        label: label,
        speak: message.isEmpty || message == label ? null : message,
        imageFile: imageFile,
      ));
    }

    if (words.isEmpty) {
      throw const ObzFormatException('לא נמצאו מילים בלוח — אולי הקובץ ריק?');
    }
    return ObzImportResult(
      words: words,
      boardsCount: 1,
      imagesCount: words.where((w) => w.imageFile != null).length,
    );
  }

  /// Buttons in reading order: HOME page first, then pages by id; within a
  /// page by cell location. Buttons on no page come last.
  List<Map<String, Object?>> _orderedButtons(SqliteReader db) {
    final buttons = db.rows('buttons');
    final byResource = <int, Map<String, Object?>>{
      for (final b in buttons)
        if (b['resource_id'] is int) b['resource_id'] as int: b,
    };
    if (!db.hasTable('button_box_cells') ||
        !db.hasTable('button_box_instances') ||
        !db.hasTable('pages')) {
      return buttons;
    }

    int? home;
    if (db.hasTable('special_pages')) {
      for (final s in db.rows('special_pages')) {
        if ('${s['name']}'.toUpperCase() == 'HOME' && s['page_id'] is int) {
          home = s['page_id'] as int;
        }
      }
    }
    final pageIds = [
      for (final p in db.rows('pages'))
        if (p['id'] is int) p['id'] as int,
    ]..sort((a, b) {
        if (a == home) return -1;
        if (b == home) return 1;
        return a.compareTo(b);
      });

    final boxesOfPage = <int, List<int>>{};
    for (final i in db.rows('button_box_instances')) {
      final page = i['page_id'];
      final box = i['button_box_id'];
      if (page is int && box is int) (boxesOfPage[page] ??= []).add(box);
    }
    final cellsOfBox = <int, List<Map<String, Object?>>>{};
    for (final c in db.rows('button_box_cells')) {
      final box = c['button_box_id'];
      if (box is int) (cellsOfBox[box] ??= []).add(c);
    }
    int loc(Map<String, Object?> c) => c['location'] is int ? c['location'] as int : 0;

    final out = <Map<String, Object?>>[];
    final placed = <int>{};
    for (final page in pageIds) {
      for (final box in boxesOfPage[page] ?? const <int>[]) {
        final cells = [...?cellsOfBox[box]]..sort((a, b) => loc(a).compareTo(loc(b)));
        for (final c in cells) {
          final res = c['resource_id'];
          final b = res is int ? byResource[res] : null;
          if (b != null && placed.add(res as int)) out.add(b);
        }
      }
    }
    for (final b in buttons) {
      final res = b['resource_id'];
      if (res is! int || !placed.contains(res)) out.add(b);
    }
    return out;
  }

  /// Custom pictures from Images.c4s by symbol rid — uncompressed raster
  /// images only; anything else is skipped (the word still imports).
  Map<String, ({Uint8List data, String ext})> _pictures(Uint8List? bytes) {
    final out = <String, ({Uint8List data, String ext})>{};
    if (bytes == null) return out;
    try {
      final db = SqliteReader(bytes);
      if (!db.hasTable('symbols')) return out;
      for (final s in db.rows('symbols')) {
        final data = s['data'];
        if (s['rid'] == null || data is! Uint8List || data.isEmpty) continue;
        final ext = _rasterExt(data);
        if (ext != null) out['${s['rid']}'] = (data: data, ext: ext);
      }
    } catch (_) {
      // Pictures are a bonus — a picture database we can't read never
      // blocks the words.
    }
    return out;
  }

  static String? _rasterExt(Uint8List d) {
    if (d.length > 8 && d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47) {
      return 'png';
    }
    if (d.length > 3 && d[0] == 0xFF && d[1] == 0xD8 && d[2] == 0xFF) return 'jpg';
    if (d.length > 6 && d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46) return 'gif';
    return null;
  }

  /// Hebrew without nikud/cantillation — so "מֶלון" and "מלון" are one word.
  static String _plain(String s) =>
      s.replaceAll(RegExp('[֑-ׇ]'), '').trim();
}
