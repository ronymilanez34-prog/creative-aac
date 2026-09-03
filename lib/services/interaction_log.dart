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
  static const _maxEntries = 5000;

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
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.add(jsonEncode(entry));
    // Cap so the log can't grow without bound; oldest entries drop first.
    final start = list.length > _maxEntries ? list.length - _maxEntries : 0;
    await prefs.setStringList(_key, list.sublist(start));
  }

  Future<List<Map<String, dynamic>>> entries() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const [])
        .map((s) => jsonDecode(s))
        .whereType<Map<String, dynamic>>()
        .toList();
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

  /// Full log as JSON — for the clinician export.
  Future<String> export() async =>
      const JsonEncoder.withIndent('  ').convert(await entries());

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
