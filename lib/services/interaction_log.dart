import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// On-device interaction log — the measurement backbone for the pilot.
///
/// Every selection records what was on screen, what was chosen, at which
/// screen position, by whom (user / partner modelling), and how long it took.
/// From this the clinician derives the pilot measures: self-initiation,
/// vocabulary diversity, support level over time — and the position-bias
/// signal (choices correlating with screen position rather than content).
///
/// Everything stays on this device. Nothing is uploaded. The visible logging
/// indicator + the user's own consent flow are a product requirement before
/// the pilot (see docs/TEN_WAYS.md, way 9).
class InteractionLog {
  static const _key = 'interaction_log_v1';

  // SharedPreferences rewrites its whole backing file on every write, so the
  // cap bounds the per-tap cost. Enough for weeks of pilot sessions; move to
  // an append-friendly store (sqlite/file) before scaling beyond the pilot.
  static const _maxEntries = 2000;

  /// In-memory write-through cache so each append reads the store at most
  /// once per app run.
  List<String>? _cache;

  Future<List<String>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    return _cache = List<String>.of(prefs.getStringList(_key) ?? const []);
  }

  /// A chip/confirm/text selection inside the creation loop.
  Future<void> logSelection({
    required List<String> shownOptions,
    required String chosen,
    required int chosenIndex,
    required String kind, // 'chip' | 'text' | 'confirm'
    required String source, // 'user' | 'partner'
    required bool lowEnergy,
    required int latencyMs,
  }) =>
      _append({
        'type': 'selection',
        'ts': DateTime.now().toIso8601String(),
        'shown': shownOptions,
        'chosen': chosen,
        'index': chosenIndex,
        'kind': kind,
        'source': source,
        'lowEnergy': lowEnergy,
        'latencyMs': latencyMs,
      });

  /// A quick-fire (emergency strip) press — always logged, it is the most
  /// important signal for partners to review.
  Future<void> logQuickFire(String label) => _append({
        'type': 'quickfire',
        'ts': DateTime.now().toIso8601String(),
        'label': label,
      });

  Future<void> _append(Map<String, Object?> entry) async {
    final list = await _load();
    list.add(jsonEncode(entry));
    // Cap so the log can't grow without bound; oldest entries drop first.
    if (list.length > _maxEntries) {
      list.removeRange(0, list.length - _maxEntries);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, list);
  }

  Future<List<Map<String, dynamic>>> entries() async {
    final out = <Map<String, dynamic>>[];
    for (final s in await _load()) {
      // One corrupt row must not take down weeks of pilot data — skip it.
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) out.add(decoded);
      } on FormatException {
        // ignore the bad entry
      }
    }
    return out;
  }

  /// Chip selections per screen position. A heavily skewed distribution is
  /// the position-bias alert for the clinician: choices may be tracking
  /// screen location, not content.
  Future<Map<int, int>> positionCounts() async {
    final counts = <int, int>{};
    for (final e in await entries()) {
      if (e['type'] == 'selection' && e['kind'] == 'chip') {
        final i = e['index'];
        if (i is int && i >= 0) counts[i] = (counts[i] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Free-text inputs the user typed, counted — the "desire paths" signal:
  /// a phrase typed again and again is a path worn in the grass, a candidate
  /// for the script library or the interests list.
  Future<Map<String, int>> freeTextCounts() async {
    final counts = <String, int>{};
    for (final e in await entries()) {
      if (e['type'] == 'selection' && e['kind'] == 'text') {
        final t = (e['chosen'] ?? '').toString().trim();
        if (t.isNotEmpty) counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Full log as JSON — for the clinician export.
  Future<String> export() async =>
      const JsonEncoder.withIndent('  ').convert(await entries());

  Future<void> clear() async {
    _cache = <String>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
