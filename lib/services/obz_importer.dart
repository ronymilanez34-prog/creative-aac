import 'dart:collection';
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
///
/// Only boards the user can actually reach count. A real export (21.10, a
/// friend's TouchChat board: 94 boards in the file, 25 reachable from home)
/// carries pages nobody navigates to any more — their words are not the
/// user's language. So an .obz with a manifest root is walked from that root
/// through `load_board` links, breadth-first (home first, then by depth),
/// and unlinked boards are skipped. Without a manifest/root every board is
/// taken, as before, so a bare .obf or a sloppy package still imports.
class ObzImporter {
  /// Words beyond this are dropped — enough for any real board set, and it
  /// keeps a malformed/huge file from filling the device.
  static const int maxWords = 300;

  /// Pages kept in the layout (the map of the board). A real export has
  /// a few dozen reachable pages; this keeps a runaway package bounded.
  static const int maxPages = 120;

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

    // Where to start: the manifest's root board (the user's home screen).
    // The manifest also maps board ids to paths — load_board links in the
    // wild come as a path, sometimes only as an id.
    String? rootPath;
    final idToPath = <String, String>{};
    final manifest = _tryJson(entries['manifest.json']);
    if (manifest != null) {
      final root = manifest['root'];
      if (root is String && root.trim().isNotEmpty) {
        rootPath = _normalize(root.trim());
      }
      final boards = (manifest['paths'] is Map)
          ? (manifest['paths'] as Map)['boards']
          : null;
      if (boards is Map) {
        boards.forEach((id, p) {
          if (p is String) idToPath['$id'] = _normalize(p);
        });
      }
    }

    final ctx = _ImportContext(images);
    if (rootPath != null && entries.containsKey(rootPath)) {
      _walkFromRoot(rootPath, entries, idToPath, ctx);
    } else {
      _collectEveryBoard(entries, idToPath, ctx);
    }

    if (ctx.boardsCount == 0) {
      throw const ObzFormatException('לא נמצאו לוחות תקשורת בתוך הקובץ');
    }
    return ctx.result();
  }

  /// Breadth-first over `load_board` links from the root: home first, then
  /// its children, then theirs — word priority follows navigation depth, and
  /// a board no visible button leads to is never visited.
  void _walkFromRoot(
    String rootPath,
    Map<String, ArchiveFile> entries,
    Map<String, String> idToPath,
    _ImportContext ctx,
  ) {
    final queue = Queue<(String, int)>()..add((rootPath, 0));
    final seen = <String>{rootPath};
    // Built only when a link carries an id the manifest does not know.
    Map<String, String>? idIndex;

    while (queue.isNotEmpty) {
      final (path, depth) = queue.removeFirst();
      final board = _tryJson(entries[path]);
      if (board == null) continue;
      ctx.boardsCount++;
      ctx.rootId ??= path;
      String? resolve(Map link) => _resolveLink(
            link,
            from: path,
            entries: entries,
            idToPath: idToPath,
            idIndex: () => idIndex ??= _indexBoardIds(entries),
          );
      // Past the word cap the walk goes on: reachable boards are still
      // counted (never reported as orphans) and their layout is still
      // kept while the page cap allows, only new words stop.
      _collectBoard(
        board,
        ctx,
        entries: entries,
        pageId: ctx.pages.length < maxPages ? path : null,
        resolveLink: resolve,
      );

      for (final link in _visibleLinks(board)) {
        final target = resolve(link);
        if (target != null && seen.add(target)) queue.add((target, depth + 1));
      }
    }

    ctx.unreachableBoards = entries.keys
        .where((n) => n.toLowerCase().endsWith('.obf') && !seen.contains(n))
        .length;
  }

  /// No usable root: every board in the package, the listed ones first.
  void _collectEveryBoard(
    Map<String, ArchiveFile> entries,
    Map<String, String> idToPath,
    _ImportContext ctx,
  ) {
    final boardPaths = <String>[
      ...idToPath.values,
      for (final name in entries.keys)
        if (name.toLowerCase().endsWith('.obf')) name,
    ];
    final seenBoards = <String>{};
    Map<String, String>? idIndex;
    for (final path in boardPaths) {
      if (!seenBoards.add(path)) continue;
      final board = _tryJson(entries[path]);
      if (board == null) continue;
      ctx.boardsCount++;
      ctx.rootId ??= path;
      _collectBoard(
        board,
        ctx,
        entries: entries,
        pageId: ctx.pages.length < maxPages ? path : null,
        resolveLink: (link) => _resolveLink(
          link,
          from: path,
          entries: entries,
          idToPath: idToPath,
          idIndex: () => idIndex ??= _indexBoardIds(entries),
        ),
      );
      if (ctx.full && ctx.pages.length >= maxPages) break;
    }
  }

  /// The `load_board` objects of a board's visible buttons. A hidden
  /// button's link is a path the user cannot take, so it does not count.
  Iterable<Map> _visibleLinks(Map<String, dynamic> board) sync* {
    for (final b in (board['buttons'] as List? ?? const []).whereType<Map>()) {
      if (b['hidden'] == true) continue;
      final link = b['load_board'];
      if (link is Map) yield link;
    }
  }

  /// Turns a `load_board` object into an entry name in the package, or null
  /// when it points nowhere we can follow (external url, missing file).
  String? _resolveLink(
    Map link, {
    required String from,
    required Map<String, ArchiveFile> entries,
    required Map<String, String> idToPath,
    required Map<String, String> Function() idIndex,
  }) {
    final path = link['path'];
    if (path is String && path.trim().isNotEmpty) {
      final p = _normalize(path.trim());
      if (entries.containsKey(p)) return p;
      // Some exporters write the link relative to the linking board.
      final dir = from.contains('/') ? from.substring(0, from.lastIndexOf('/') + 1) : '';
      if (dir.isNotEmpty && entries.containsKey('$dir$p')) return '$dir$p';
    }
    final id = link['id'];
    if (id != null && '$id'.trim().isNotEmpty) {
      final key = '$id'.trim();
      final fromManifest = idToPath[key];
      if (fromManifest != null && entries.containsKey(fromManifest)) {
        return fromManifest;
      }
      final indexed = idIndex()[key];
      if (indexed != null) return indexed;
    }
    return null;
  }

  /// board id → entry name, from the boards' own `id` fields. Only parsed
  /// when a link names an id the manifest does not list.
  Map<String, String> _indexBoardIds(Map<String, ArchiveFile> entries) {
    final out = <String, String>{};
    for (final name in entries.keys) {
      if (!name.toLowerCase().endsWith('.obf')) continue;
      final board = _tryJson(entries[name]);
      final id = board?['id'];
      if (id != null && '$id'.trim().isNotEmpty) out.putIfAbsent('$id'.trim(), () => name);
    }
    return out;
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
    ctx.rootId = 'root';
    _collectBoard(board, ctx, pageId: 'root');
    return ctx.result();
  }

  /// Collects a board's words into [ctx] and, when [pageId] is given, its
  /// layout too: every visible button at its grid position, with its
  /// picture, its color and the page its `load_board` opens ([resolveLink]
  /// turns the link into a page id; null drops it).
  void _collectBoard(
    Map<String, dynamic> board,
    _ImportContext ctx, {
    Map<String, ArchiveFile>? entries,
    String? pageId,
    String? Function(Map link)? resolveLink,
  }) {
    final buttonList = (board['buttons'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final byId = {for (final b in buttonList) '${b['id']}': b};

    final images = <String, Map>{};
    for (final img in (board['images'] as List? ?? const []).whereType<Map>()) {
      images['${img['id']}'] = img;
    }

    // grid.order preserves the visual layout — the order the user knows,
    // and (for the layout) where each button sits.
    final ordered = <Map>[];
    final positions = <String, (int, int)>{};
    final grid = board['grid'];
    if (grid is Map && grid['order'] is List) {
      var r = 0;
      for (final row in grid['order'] as List) {
        if (row is! List) continue;
        for (var c = 0; c < row.length; c++) {
          final id = row[c];
          if (id == null) continue;
          final b = byId.remove('$id');
          if (b != null) {
            ordered.add(b);
            positions['$id'] = (r, c);
          }
        }
        r++;
      }
    }
    ordered.addAll(byId.values);

    final pageButtons = <BoardButton>[];
    for (final button in ordered) {
      if (button['hidden'] == true) continue;
      final label = (button['label'] ?? '').toString().trim();
      final speak = (button['vocalization'] ?? '').toString().trim();
      final imageFile =
          _imageFor(images['${button['image_id']}'], ctx, entries);

      // The vocabulary: labeled, new words, up to the cap.
      if (label.isNotEmpty &&
          !ctx.full &&
          ctx.seenLabels.add(label.toLowerCase())) {
        ctx.words.add(BoardWord(
          id: 'w${ctx.words.length}',
          label: label,
          speak: speak.isEmpty ? null : speak,
          imageFile: imageFile,
        ));
      }

      // The layout: every button in the grid that shows something or
      // leads somewhere, exactly where it is.
      final pos = positions['${button['id']}'];
      if (pageId == null || pos == null) continue;
      final link = button['load_board'];
      final target = (link is Map && resolveLink != null) ? resolveLink(link) : null;
      if (label.isEmpty && imageFile == null && target == null) continue;
      final color = (button['background_color'] ?? '').toString().trim();
      pageButtons.add(BoardButton(
        id: '${button['id']}',
        row: pos.$1,
        col: pos.$2,
        label: label,
        speak: speak.isEmpty ? null : speak,
        imageFile: imageFile,
        backgroundColor: color.isEmpty ? null : color,
        loadBoardId: target,
      ));
    }

    if (pageId != null) {
      // The used extent, not the declared one (TouchChat's converter
      // declares 10x10 for a 5x4 page). Positions themselves never move.
      var rows = 0;
      var cols = 0;
      for (final b in pageButtons) {
        if (b.row + 1 > rows) rows = b.row + 1;
        if (b.col + 1 > cols) cols = b.col + 1;
      }
      final declaredRows = (grid is Map ? grid['rows'] : null);
      final declaredCols = (grid is Map ? grid['columns'] : null);
      if (rows == 0) rows = declaredRows is num ? declaredRows.toInt() : 1;
      if (cols == 0) cols = declaredCols is num ? declaredCols.toInt() : 1;
      final name = (board['name'] ?? '').toString().trim();
      ctx.pages.add(BoardPage(
        id: pageId,
        name: name.isEmpty ? pageId : name,
        rows: rows < 1 ? 1 : rows,
        columns: cols < 1 ? 1 : cols,
        buttons: pageButtons,
      ));
    }
  }

  /// The stored file name of a button's image — written once per distinct
  /// image, so a picture used on several pages (or by a word and by its
  /// button) is stored once.
  String? _imageFor(Map? image, _ImportContext ctx, Map<String, ArchiveFile>? entries) {
    if (image == null) return null;
    final key = image['path'] is String
        ? 'path:${_normalize(image['path'] as String)}'
        : image['data'] is String
            ? 'data:${(image['data'] as String).length}:${(image['data'] as String).hashCode}'
            : null;
    if (key == null) return _writeImage(image, ctx, entries);
    if (ctx.imageFiles.containsKey(key)) return ctx.imageFiles[key];
    return ctx.imageFiles[key] = _writeImage(image, ctx, entries);
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
  final pages = <BoardPage>[];
  String? rootId;

  /// Distinct images already written (see _imageFor).
  final imageFiles = <String, String?>{};
  int boardsCount = 0;
  int unreachableBoards = 0;
  int imagesWritten = 0;

  bool get full => words.length >= ObzImporter.maxWords;

  ObzImportResult result() {
    if (words.isEmpty) {
      throw const ObzFormatException('לא נמצאו מילים בלוח — אולי הקובץ ריק?');
    }
    return ObzImportResult(
      words: words,
      boardsCount: boardsCount,
      unreachableBoards: unreachableBoards,
      imagesCount: words.where((w) => w.imageFile != null).length,
      layout: pages.isEmpty
          ? null
          : BoardLayout(rootId: rootId ?? pages.first.id, pages: pages),
    );
  }
}

class ObzImportResult {
  const ObzImportResult({
    required this.words,
    required this.boardsCount,
    required this.imagesCount,
    this.unreachableBoards = 0,
    this.layout,
  });

  final List<BoardWord> words;

  /// The board as a map — pages, positions, links — for the screen that
  /// rides on the user's own layout. Null only when no page was parsed.
  final BoardLayout? layout;

  /// Boards reachable from home (every board, when the package has no
  /// root). Words stop at [ObzImporter.maxWords], the count does not.
  final int boardsCount;

  /// Boards in the package that no visible navigation path reaches — left
  /// out on purpose; shown to the importer so "fewer words than the file"
  /// is never a mystery.
  final int unreachableBoards;

  final int imagesCount;
}

/// A user-presentable import failure (message is in Hebrew, shown as-is).
class ObzFormatException implements Exception {
  const ObzFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}
