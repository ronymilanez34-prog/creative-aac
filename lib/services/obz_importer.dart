import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/board.dart';
import 'image_sink.dart';

/// Parses Open Board Format files — the open standard AAC apps use to
/// export communication boards (openboardformat.org).
///
/// Two shapes are supported:
///  • `.obz` — a zip package: manifest.json + one `.obf` per board + the
///    image files themselves.
///  • `.obf` — a single board as plain JSON (images only if embedded as
///    data URIs).
///
/// The importer extracts every visible, labeled button into a [BoardWord]
/// and hands its image to an [ImageSink], so the app can show the user the
/// exact pictures they already know from their own device. No dart:io here —
/// the same parser runs on web (with a [NoopImageSink], words-only).
class ObzImporter {
  /// Words beyond this are dropped — enough for any real board set, and it
  /// keeps a malformed/huge file from filling the device.
  static const int maxWords = 300;

  /// Parses [bytes] (an .obz or .obf file) and hands button images to
  /// [images]. Throws [ObzFormatException] when the file isn't a board.
  Future<ObzImportResult> import({
    required Uint8List bytes,
    required ImageSink images,
  }) async {
    if (_looksLikeZip(bytes)) return _importObz(bytes, images);
    return _importSingleObf(bytes, images);
  }

  bool _looksLikeZip(Uint8List b) => b.length > 2 && b[0] == 0x50 && b[1] == 0x4B;

  Future<ObzImportResult> _importObz(Uint8List bytes, ImageSink images) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ObzFormatException('הקובץ לא נפתח — ודאו שזה קובץ ‎.obz שיוצא מאפליקציית התקשורת');
    }

    // Entry names sometimes carry a leading "./" — normalize once.
    final entries = <String, ArchiveFile>{};
    for (final f in archive) {
      if (f.isFile) entries[_normalize(f.name)] = f;
    }

    // Board order decides word priority: the root board (the user's home
    // screen — their most-used words) first, then the rest.
    final boardPaths = <String>[];
    final manifest = _tryJson(entries['manifest.json']);
    if (manifest != null) {
      final root = manifest['root'];
      if (root is String) boardPaths.add(_normalize(root));
      final boards = (manifest['paths'] is Map) ? (manifest['paths'] as Map)['boards'] : null;
      if (boards is Map) {
        for (final p in boards.values) {
          if (p is String) boardPaths.add(_normalize(p));
        }
      }
    }
    for (final name in entries.keys) {
      if (name.toLowerCase().endsWith('.obf')) boardPaths.add(name);
    }

    final ctx = _ImportContext(images);
    final seenBoards = <String>{};
    for (final path in boardPaths) {
      if (!seenBoards.add(path)) continue;
      final board = _tryJson(entries[path]);
      if (board == null) continue;
      ctx.boardsCount++;
      _collectBoard(board, ctx, entries: entries);
      if (ctx.full) break;
    }

    if (ctx.boardsCount == 0) {
      throw const ObzFormatException('לא נמצאו לוחות תקשורת בתוך הקובץ');
    }
    return ctx.result();
  }

  Future<ObzImportResult> _importSingleObf(Uint8List bytes, ImageSink images) async {
    final Map<String, dynamic> board;
    try {
      board = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const ObzFormatException('הקובץ לא נפתח — ודאו שזה קובץ ‎.obf או ‎.obz');
    }
    final ctx = _ImportContext(images);
    ctx.boardsCount = 1;
    _collectBoard(board, ctx);
    return ctx.result();
  }

  void _collectBoard(
    Map<String, dynamic> board,
    _ImportContext ctx, {
    Map<String, ArchiveFile>? entries,
  }) {
    final buttonList = (board['buttons'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final byId = {for (final b in buttonList) '${b['id']}': b};

    final images = <String, Map>{};
    for (final img in (board['images'] as List? ?? const []).whereType<Map>()) {
      images['${img['id']}'] = img;
    }

    // grid.order preserves the visual layout — the order the user knows.
    final ordered = <Map>[];
    final grid = board['grid'];
    if (grid is Map && grid['order'] is List) {
      for (final row in grid['order'] as List) {
        if (row is! List) continue;
        for (final id in row) {
          final b = id == null ? null : byId.remove('$id');
          if (b != null) ordered.add(b);
        }
      }
    }
    ordered.addAll(byId.values);

    for (final button in ordered) {
      if (ctx.full) return;
      if (button['hidden'] == true) continue;
      final label = (button['label'] ?? '').toString().trim();
      if (label.isEmpty) continue;
      if (!ctx.seenLabels.add(label.toLowerCase())) continue;

      final speak = (button['vocalization'] ?? '').toString().trim();
      final imageFile = _writeImage(images['${button['image_id']}'], ctx, entries);

      ctx.words.add(BoardWord(
        id: 'w${ctx.words.length}',
        label: label,
        speak: speak.isEmpty ? null : speak,
        imageFile: imageFile,
      ));
    }
  }

  /// Writes a button's image into the images dir; returns its file name, or
  /// null when there's no usable image (external-URL-only images are skipped
  /// on purpose — import must work offline).
  String? _writeImage(Map? image, _ImportContext ctx, Map<String, ArchiveFile>? entries) {
    if (image == null) return null;

    Uint8List? data;
    String? ext;

    final dataUri = image['data'];
    if (dataUri is String && dataUri.startsWith('data:')) {
      final comma = dataUri.indexOf(',');
      if (comma > 0) {
        try {
          data = base64Decode(dataUri.substring(comma + 1).trim());
          ext = _extFromMime(dataUri.substring(5, comma));
        } catch (_) {
          data = null;
        }
      }
    }

    if (data == null && entries != null && image['path'] is String) {
      final entry = entries[_normalize(image['path'] as String)];
      if (entry != null) {
        data = Uint8List.fromList(entry.content as List<int>);
        ext = _extFromName(entry.name);
      }
    }

    if (data == null || data.isEmpty) return null;
    ext ??= _extFromMime((image['content_type'] ?? '').toString());
    if (ext == null) return null;

    return ctx.images.write('img_${ctx.imagesWritten++}.$ext', data);
  }

  String _normalize(String name) => name.startsWith('./') ? name.substring(2) : name;

  Map<String, dynamic>? _tryJson(ArchiveFile? f) {
    if (f == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(f.content as List<int>));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _extFromMime(String mime) {
    final m = mime.split(';').first.trim().toLowerCase();
    switch (m) {
      case 'image/png':
        return 'png';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/svg+xml':
        return 'svg';
    }
    return null;
  }

  String? _extFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'}.contains(ext)
        ? (ext == 'jpeg' ? 'jpg' : ext)
        : null;
  }
}

class _ImportContext {
  _ImportContext(this.images);

  final ImageSink images;
  final words = <BoardWord>[];
  final seenLabels = <String>{};
  int boardsCount = 0;
  int imagesWritten = 0;

  bool get full => words.length >= ObzImporter.maxWords;

  ObzImportResult result() {
    if (words.isEmpty) {
      throw const ObzFormatException('לא נמצאו מילים בלוח — אולי הקובץ ריק?');
    }
    return ObzImportResult(
      words: words,
      boardsCount: boardsCount,
      imagesCount: words.where((w) => w.imageFile != null).length,
    );
  }
}

class ObzImportResult {
  const ObzImportResult({
    required this.words,
    required this.boardsCount,
    required this.imagesCount,
  });

  final List<BoardWord> words;
  final int boardsCount;
  final int imagesCount;
}

/// A user-presentable import failure (message is in Hebrew, shown as-is).
class ObzFormatException implements Exception {
  const ObzFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}
