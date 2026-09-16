/// Full local backup — the answer to "המכשיר שכח את הכול" (USER_LENS 2.3).
///
/// Everything the app owns lives in [SharedPreferences] (on the web:
/// browser storage — one cleared history away from gone): the profile the
/// clinician built, every saved story with its pictures, the imported
/// board (words + web images), the interaction log, chip positions. A
/// backup is a typed snapshot of ALL of it in one JSON file; restore
/// replaces the device state with the file's.
///
/// Known gap: on-device (non-web) board IMAGE FILES live outside
/// SharedPreferences and are not carried yet — the pilot runs in the
/// browser, where images are data URIs inside the snapshot.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kFormat = 'creative-aac-backup';
const _kVersion = 1;

/// Encodes a typed snapshot of preference values. Values keep their exact
/// runtime type through the trip: String / bool / int / double /
/// List&lt;String&gt;.
String encodeSnapshot(Map<String, Object> values, {int? exportedAtMs}) {
  final entries = <String, Map<String, Object>>{};
  values.forEach((key, v) {
    if (v is String) {
      entries[key] = {'t': 's', 'v': v};
    } else if (v is bool) {
      entries[key] = {'t': 'b', 'v': v};
    } else if (v is int) {
      entries[key] = {'t': 'i', 'v': v};
    } else if (v is double) {
      entries[key] = {'t': 'd', 'v': v};
    } else if (v is List) {
      entries[key] = {'t': 'l', 'v': [for (final e in v) e.toString()]};
    }
  });
  return jsonEncode({
    'format': _kFormat,
    'version': _kVersion,
    'exportedAtMs': exportedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    'entries': entries,
  });
}

/// Decodes a snapshot back to typed values. Throws [FormatException] when
/// the text is not a creative-aac backup — callers validate BEFORE any
/// destructive step.
Map<String, Object> decodeSnapshot(String raw) {
  final Object? j;
  try {
    j = jsonDecode(raw);
  } catch (_) {
    throw const FormatException('לא קובץ JSON תקין');
  }
  if (j is! Map || j['format'] != _kFormat || j['entries'] is! Map) {
    throw const FormatException('הקובץ אינו גיבוי של תקשורת חלופית יוצרת');
  }
  final out = <String, Object>{};
  (j['entries'] as Map).forEach((key, e) {
    if (key is! String || e is! Map) return;
    final t = e['t'];
    final v = e['v'];
    switch (t) {
      case 's':
        if (v is String) out[key] = v;
      case 'b':
        if (v is bool) out[key] = v;
      case 'i':
        if (v is int) out[key] = v;
      case 'd':
        if (v is num) out[key] = v.toDouble();
      case 'l':
        if (v is List) out[key] = [for (final e in v) e.toString()];
    }
  });
  return out;
}

/// Snapshot of everything currently stored.
Future<String> exportAll() async {
  final prefs = await SharedPreferences.getInstance();
  final values = <String, Object>{};
  for (final key in prefs.getKeys()) {
    final v = prefs.get(key);
    if (v != null) values[key] = v;
  }
  return encodeSnapshot(values);
}

/// Replaces the device state with the backup's. The file is parsed and
/// validated FIRST — a bad file never wipes anything. Returns how many
/// entries were restored.
Future<int> restoreAll(String raw) async {
  final values = decodeSnapshot(raw);
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  for (final e in values.entries) {
    final v = e.value;
    if (v is String) {
      await prefs.setString(e.key, v);
    } else if (v is bool) {
      await prefs.setBool(e.key, v);
    } else if (v is int) {
      await prefs.setInt(e.key, v);
    } else if (v is double) {
      await prefs.setDouble(e.key, v);
    } else if (v is List<String>) {
      await prefs.setStringList(e.key, v);
    }
  }
  return values.length;
}
