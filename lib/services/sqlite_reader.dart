import 'dart:convert';
import 'dart:typed_data';

/// A tiny, read-only SQLite reader in pure Dart.
///
/// Why it exists: AAC apps (TouchChat first) save their boards as SQLite
/// databases. The app has no SQLite on the web, and the board must be read
/// ON the device — a friend's board never has to leave it to be imported.
/// So this reads the documented file format directly
/// (https://www.sqlite.org/fileformat.html): table b-trees, records,
/// overflow pages. Nothing else — no indexes, no writing, no WAL.
///
/// Web-safe on purpose: no `getInt64` (not supported when compiled to JS);
/// 64-bit integers are assembled from two 32-bit halves.
class SqliteReader {
  SqliteReader(Uint8List bytes) : _b = bytes, _d = ByteData.sublistView(bytes) {
    if (!isSqlite(bytes)) {
      throw const SqliteFormatException('not a SQLite database');
    }
    final raw = _d.getUint16(16);
    _pageSize = raw == 1 ? 65536 : raw;
    if (_pageSize < 512 || _pageSize > 65536 || (_pageSize & (_pageSize - 1)) != 0) {
      throw const SqliteFormatException('bad page size');
    }
    _usable = _pageSize - _b[20];
    _encoding = _d.getUint32(56);
    if (_b.length < _pageSize) {
      throw const SqliteFormatException('file shorter than one page');
    }
  }

  static final List<int> _magic = utf8.encode('SQLite format 3\u0000');

  /// True when [bytes] start with the SQLite header string.
  static bool isSqlite(Uint8List bytes) {
    if (bytes.length < 100) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  final Uint8List _b;
  final ByteData _d;
  late final int _pageSize;
  late final int _usable;
  late final int _encoding; // 1 utf-8, 2 utf-16le, 3 utf-16be (0 = utf-8)

  Map<String, _Table>? _schema;

  /// Table names in the database (excluding sqlite_ internals).
  List<String> get tableNames =>
      _tables.keys.where((n) => !n.startsWith('sqlite_')).toList();

  bool hasTable(String name) => _tables.containsKey(name.toLowerCase());

  /// Column names of [table], in declaration order.
  List<String> columns(String table) => _table(table).columns;

  /// Every row of [table] as column → value (int, double, String,
  /// Uint8List or null), in rowid order. An INTEGER PRIMARY KEY column
  /// carries the rowid, as in SQLite itself.
  List<Map<String, Object?>> rows(String table) {
    final t = _table(table);
    final out = <Map<String, Object?>>[];
    _walk(t.rootPage, (rowid, values) {
      final row = <String, Object?>{};
      for (var i = 0; i < t.columns.length; i++) {
        Object? v = i < values.length ? values[i] : null;
        if (i == t.rowidColumn && v == null) v = rowid;
        row[t.columns[i]] = v;
      }
      out.add(row);
    }, depth: 0);
    return out;
  }

  // ---------------------------------------------------------------- schema

  Map<String, _Table> get _tables => _schema ??= _readSchema();

  _Table _table(String name) {
    final t = _tables[name.toLowerCase()];
    if (t == null) throw SqliteFormatException('no table "$name"');
    return t;
  }

  Map<String, _Table> _readSchema() {
    final out = <String, _Table>{};
    _walk(1, (rowid, v) {
      // sqlite_master: type, name, tbl_name, rootpage, sql
      if (v.length < 5 || v[0] != 'table') return;
      final name = v[1];
      final root = v[3];
      final sql = v[4];
      if (name is! String || root is! int || root <= 0) return;
      final cols = parseColumns(sql is String ? sql : '');
      out[name.toLowerCase()] = _Table(root, cols.names, cols.rowidIndex);
    }, depth: 0);
    return out;
  }

  /// Column names (and which one, if any, aliases the rowid) from a
  /// CREATE TABLE statement. Public for testing.
  static ({List<String> names, int rowidIndex}) parseColumns(String sql) {
    final open = sql.indexOf('(');
    final close = sql.lastIndexOf(')');
    if (open < 0 || close <= open) return (names: const [], rowidIndex: -1);
    final body = sql.substring(open + 1, close);
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    String? quote;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        quote = c;
      } else if (c == '[') {
        quote = ']';
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (c == ',' && depth == 0) {
        parts.add(body.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(body.substring(start));

    const constraints = {'primary', 'unique', 'check', 'foreign', 'constraint'};
    final names = <String>[];
    var rowid = -1;
    for (final raw in parts) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      // Table constraints may hug their parenthesis: "UNIQUE(a,b)".
      final first =
          (RegExp(r'^[A-Za-z_]+').firstMatch(p)?.group(0) ?? '').toLowerCase();
      if (constraints.contains(first)) continue;
      String name;
      final q = p[0];
      if (q == '"' || q == '`' || q == '[') {
        final end = p.indexOf(q == '[' ? ']' : q, 1);
        name = end > 0 ? p.substring(1, end) : p.substring(1);
      } else {
        name = p.split(RegExp(r'\s+')).first;
      }
      // What follows the name (closing quote included) — the type and
      // constraints. "INTEGER PRIMARY KEY" makes the column the rowid.
      final rest = p
          .substring(p.indexOf(name) + name.length)
          .replaceFirst(RegExp(r'^["`\]]'), '')
          .toLowerCase();
      if (RegExp(r'^\s*integer\s+primary\s+key').hasMatch(rest)) {
        rowid = names.length;
      }
      names.add(name);
    }
    return (names: names, rowidIndex: rowid);
  }

  // ---------------------------------------------------------------- b-trees

  int _pageOffset(int page) => (page - 1) * _pageSize;

  void _walk(int page, void Function(int rowid, List<Object?> values) onRow,
      {required int depth}) {
    if (depth > 64) throw const SqliteFormatException('b-tree too deep');
    final base = _pageOffset(page);
    if (base < 0 || base + _pageSize > _b.length) {
      throw SqliteFormatException('page $page out of range');
    }
    final h = page == 1 ? base + 100 : base; // page 1 carries the file header
    final type = _b[h];
    final cells = _d.getUint16(h + 3);
    final interior = type == 0x05;
    if (type != 0x05 && type != 0x0d) {
      throw SqliteFormatException('page $page is not a table b-tree ($type)');
    }
    final ptrs = h + (interior ? 12 : 8);
    for (var i = 0; i < cells; i++) {
      final cell = base + _d.getUint16(ptrs + i * 2);
      if (interior) {
        _walk(_d.getUint32(cell), onRow, depth: depth + 1);
      } else {
        _leafCell(cell, onRow);
      }
    }
    if (interior) _walk(_d.getUint32(h + 8), onRow, depth: depth + 1);
  }

  void _leafCell(int at, void Function(int rowid, List<Object?> values) onRow) {
    var p = at;
    final (size, n1) = _varint(p);
    p += n1;
    final (rowid, n2) = _varint(p);
    p += n2;
    final payload = _payload(p, size);
    onRow(rowid, _record(payload));
  }

  /// The cell's full payload, following overflow pages when it spills.
  Uint8List _payload(int at, int size) {
    final u = _usable;
    final x = u - 35;
    if (size <= x) return Uint8List.sublistView(_b, at, at + size);
    final m = ((u - 12) * 32 ~/ 255) - 23;
    final k = m + ((size - m) % (u - 4));
    final local = k <= x ? k : m;
    final out = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(_b, at, at + local));
    var remaining = size - local;
    var next = _d.getUint32(at + local);
    var guard = 0;
    while (remaining > 0 && next != 0) {
      if (++guard > 1000000) throw const SqliteFormatException('overflow loop');
      final base = _pageOffset(next);
      if (base < 0 || base + _pageSize > _b.length) {
        throw const SqliteFormatException('overflow page out of range');
      }
      final take = remaining < u - 4 ? remaining : u - 4;
      out.add(Uint8List.sublistView(_b, base + 4, base + 4 + take));
      remaining -= take;
      next = _d.getUint32(base);
    }
    return out.takeBytes();
  }

  List<Object?> _record(Uint8List r) {
    final d = ByteData.sublistView(r);
    var p = 0;
    final (headerSize, n) = _varintIn(r, 0);
    p = n;
    final types = <int>[];
    while (p < headerSize) {
      final (t, m) = _varintIn(r, p);
      types.add(t);
      p += m;
    }
    var at = headerSize;
    final values = <Object?>[];
    for (final t in types) {
      switch (t) {
        case 0:
          values.add(null);
        case 1:
          values.add(d.getInt8(at));
          at += 1;
        case 2:
          values.add(d.getInt16(at));
          at += 2;
        case 3:
          final v = (r[at] << 16) | (r[at + 1] << 8) | r[at + 2];
          values.add(v >= 0x800000 ? v - 0x1000000 : v);
          at += 3;
        case 4:
          values.add(d.getInt32(at));
          at += 4;
        case 5:
          final hi = d.getInt16(at);
          final lo = d.getUint32(at + 2);
          values.add(hi * 4294967296 + lo);
          at += 6;
        case 6:
          final hi = d.getInt32(at);
          final lo = d.getUint32(at + 4);
          values.add(hi * 4294967296 + lo);
          at += 8;
        case 7:
          values.add(d.getFloat64(at));
          at += 8;
        case 8:
          values.add(0);
        case 9:
          values.add(1);
        default:
          if (t >= 12 && t.isEven) {
            final len = (t - 12) ~/ 2;
            values.add(Uint8List.fromList(r.sublist(at, at + len)));
            at += len;
          } else if (t >= 13) {
            final len = (t - 13) ~/ 2;
            values.add(_text(r, at, len));
            at += len;
          } else {
            values.add(null); // reserved types 10/11
          }
      }
    }
    return values;
  }

  String _text(Uint8List r, int at, int len) {
    final bytes = r.sublist(at, at + len);
    if (_encoding == 2 || _encoding == 3) {
      final le = _encoding == 2;
      final units = <int>[];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        units.add(le ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  (int, int) _varint(int at) => _varintIn(_b, at);

  static (int, int) _varintIn(Uint8List b, int at) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      final c = b[at + i];
      v = v * 128 + (c & 0x7f);
      if (c & 0x80 == 0) return (v, i + 1);
    }
    return (v * 256 + b[at + 8], 9);
  }
}

class _Table {
  const _Table(this.rootPage, this.columns, this.rowidColumn);
  final int rootPage;
  final List<String> columns;
  final int rowidColumn;
}

class SqliteFormatException implements Exception {
  const SqliteFormatException(this.message);
  final String message;
  @override
  String toString() => 'SqliteFormatException: $message';
}
