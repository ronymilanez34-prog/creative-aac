/// The user's personal vocabulary, imported from their existing AAC app.
///
/// A [BoardWord] is one button from the user's own communication board: the
/// label they already know, the exact image they already recognize, and the
/// text to speak. Familiarity is the whole point — see docs/VISION.md.

library;

class BoardWord {
  const BoardWord({
    required this.id,
    required this.label,
    this.speak,
    this.imageFile,
    this.imagePath,
  });

  final String id;

  /// The text on the button — the word as the user knows it.
  final String label;

  /// What the button says out loud, when different from [label].
  final String? speak;

  /// File name of the button's image inside the app's board-images folder
  /// (relative — the folder's absolute location can change between app
  /// launches on iOS, so it is resolved at load time).
  final String? imageFile;

  /// Absolute path to the image, resolved by [BoardStore] when loading.
  /// Null when the word has no image.
  final String? imagePath;

  String get spokenText => (speak != null && speak!.trim().isNotEmpty) ? speak! : label;

  BoardWord withImagePath(String? path) => BoardWord(
        id: id,
        label: label,
        speak: speak,
        imageFile: imageFile,
        imagePath: path,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (speak != null) 'speak': speak,
        if (imageFile != null) 'imageFile': imageFile,
      };

  factory BoardWord.fromJson(Map<String, dynamic> j) => BoardWord(
        id: j['id'] as String,
        label: j['label'] as String,
        speak: j['speak'] as String?,
        imageFile: j['imageFile'] as String?,
      );
}

/// One button of one page of the user's own board, exactly where it sits.
///
/// The layout side of an import (21.10, "לא ללמד מחדש"): what the user
/// learned over years is the position, the picture and the path to the
/// next page, so all of it is kept one to one. A word list alone loses
/// the map.
class BoardButton {
  const BoardButton({
    required this.id,
    required this.row,
    required this.col,
    required this.label,
    this.speak,
    this.imageFile,
    this.imagePath,
    this.backgroundColor,
    this.loadBoardId,
  });

  final String id;

  /// Position in the page's grid (0-based), as in the file.
  final int row;
  final int col;

  final String label;
  final String? speak;
  final String? imageFile;
  final String? imagePath;

  /// The color the file gives the button ("#rrggbb" or "rgb(r, g, b)"),
  /// or null. Shown as-is; never invented (the app adds no colors the
  /// user's board does not have).
  final String? backgroundColor;

  /// The page this button opens ([BoardPage.id]), or null for a word.
  final String? loadBoardId;

  bool get isLink => loadBoardId != null;

  String get spokenText =>
      (speak != null && speak!.trim().isNotEmpty) ? speak! : label;

  BoardButton withImagePath(String? path) => BoardButton(
        id: id,
        row: row,
        col: col,
        label: label,
        speak: speak,
        imageFile: imageFile,
        imagePath: path,
        backgroundColor: backgroundColor,
        loadBoardId: loadBoardId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'row': row,
        'col': col,
        'label': label,
        if (speak != null) 'speak': speak,
        if (imageFile != null) 'imageFile': imageFile,
        if (backgroundColor != null) 'bg': backgroundColor,
        if (loadBoardId != null) 'loadBoard': loadBoardId,
      };

  factory BoardButton.fromJson(Map<String, dynamic> j) => BoardButton(
        id: '${j['id']}',
        row: (j['row'] as num?)?.toInt() ?? 0,
        col: (j['col'] as num?)?.toInt() ?? 0,
        label: (j['label'] ?? '').toString(),
        speak: j['speak'] as String?,
        imageFile: j['imageFile'] as String?,
        backgroundColor: j['bg'] as String?,
        loadBoardId: j['loadBoard'] as String?,
      );
}

/// One page of the board: its grid size and its buttons in place.
class BoardPage {
  const BoardPage({
    required this.id,
    required this.name,
    required this.rows,
    required this.columns,
    required this.buttons,
  });

  final String id;
  final String name;

  /// The grid as the user sees it. An exporter may declare a bigger grid
  /// than it fills (TouchChat's converter says 10x10 for a page that uses
  /// 5x4); the importer trims trailing empty rows and columns, so these
  /// are the used extent. Leading positions are never shifted.
  final int rows;
  final int columns;
  final List<BoardButton> buttons;

  BoardButton? at(int row, int col) {
    for (final b in buttons) {
      if (b.row == row && b.col == col) return b;
    }
    return null;
  }

  BoardPage withImagePaths(String? Function(String? imageFile) resolve) =>
      BoardPage(
        id: id,
        name: name,
        rows: rows,
        columns: columns,
        buttons: [for (final b in buttons) b.withImagePath(resolve(b.imageFile))],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rows': rows,
        'columns': columns,
        'buttons': buttons.map((b) => b.toJson()).toList(),
      };

  factory BoardPage.fromJson(Map<String, dynamic> j) => BoardPage(
        id: '${j['id']}',
        name: (j['name'] ?? '').toString(),
        rows: (j['rows'] as num?)?.toInt() ?? 1,
        columns: (j['columns'] as num?)?.toInt() ?? 1,
        buttons: (j['buttons'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BoardButton.fromJson)
            .toList(),
      );
}

/// The user's board as a map: the pages reachable from home, in the order
/// the import walked them (home first, then by depth), with their links.
class BoardLayout {
  const BoardLayout({required this.rootId, required this.pages});

  final String rootId;
  final List<BoardPage> pages;

  bool get isEmpty => pages.isEmpty;

  BoardPage? page(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  BoardPage? get home => page(rootId) ?? (pages.isEmpty ? null : pages.first);

  /// Every word button by its label (lowercased, trimmed) — the first
  /// occurrence wins, so home-page words come before deeper duplicates.
  /// This is how the companion's words find their picture on the board.
  Map<String, BoardButton> get byLabel {
    final out = <String, BoardButton>{};
    for (final p in pages) {
      for (final b in p.buttons) {
        final key = b.label.trim().toLowerCase();
        if (key.isNotEmpty) out.putIfAbsent(key, () => b);
      }
    }
    return out;
  }

  BoardLayout withImagePaths(String? Function(String? imageFile) resolve) =>
      BoardLayout(
        rootId: rootId,
        pages: [for (final p in pages) p.withImagePaths(resolve)],
      );

  Map<String, dynamic> toJson() => {
        'rootId': rootId,
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory BoardLayout.fromJson(Map<String, dynamic> j) => BoardLayout(
        rootId: '${j['rootId']}',
        pages: (j['pages'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BoardPage.fromJson)
            .toList(),
      );
}
