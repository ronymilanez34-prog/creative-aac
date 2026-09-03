import '../models/companion.dart';

/// Motor-consistency layout for generated chips (the LAMP principle:
/// consistent position, not consistent appearance, is what builds fluent
/// access — Thistle et al. 2018).
///
/// A label that has appeared before keeps its remembered slot for the rest
/// of the session; only first-ever labels are shuffled into the free slots —
/// which preserves the position-bias signal (a first appearance is still
/// random, so choices tracking screen location remain detectable) while a
/// familiar chip stops jumping around.
class ChipSlots {
  final Map<String, int> _slotByLabel = {};

  List<ChipOption> arrange(List<ChipOption> options) {
    final n = options.length;
    final placed = List<ChipOption?>.filled(n, null);
    final newcomers = <ChipOption>[];

    for (final o in options) {
      final slot = _slotByLabel[o.label];
      if (slot != null && slot < n && placed[slot] == null) {
        placed[slot] = o;
      } else {
        newcomers.add(o);
      }
    }

    newcomers.shuffle();
    var idx = 0;
    for (final o in newcomers) {
      while (idx < n && placed[idx] != null) {
        idx++;
      }
      if (idx >= n) break;
      placed[idx] = o;
      _slotByLabel[o.label] = idx;
    }

    return placed.whereType<ChipOption>().toList();
  }
}
