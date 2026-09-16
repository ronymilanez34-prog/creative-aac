/// How a growing creation travels to the model, and how its replies are
/// kept clean — the two joints of the rolling-summary contract (HANDOVER,
/// "continue from yesterday").
library;

/// Above this many characters of full creation text, and once a rolling
/// summary exists, only the newest pieces travel each turn.
const int kFullTextLimit = 1200;

/// Roughly how many characters of the newest pieces ride along when the
/// summary carries the rest. Whole pieces only — a cut mid-sentence reads
/// like a different creation.
const int kSummaryTailChars = 800;

/// What the backend sees of the creation this turn: the full text while the
/// creation is short (or before the model produced a first summary), and
/// the rolling summary plus only the newest pieces once it grew long.
({String creationSoFar, String? creationSummary}) creationContext(
  List<String> pieces,
  String? rollingSummary,
) {
  final full = pieces.join(' ');
  final summary = rollingSummary?.trim() ?? '';
  if (summary.isEmpty || full.length <= kFullTextLimit) {
    return (
      creationSoFar: full,
      creationSummary: summary.isEmpty ? null : summary,
    );
  }
  final tail = <String>[];
  var len = 0;
  for (final p in pieces.reversed) {
    if (tail.isNotEmpty && len + p.length > kSummaryTailChars) break;
    tail.insert(0, p);
    len += p.length + 1;
  }
  return (creationSoFar: tail.join(' '), creationSummary: summary);
}

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The model sometimes returns the WHOLE creation in creation_update
/// instead of only the new piece (seen live 16.9: "אריק יושב באוטובוס.
/// אריק יושב באוטובוס, גלידה בידו…"). Appending that duplicates everything,
/// so the new piece is extracted: a prefix repeating the creation so far —
/// all of it, or just its newest pieces — is stripped. Returns the empty
/// string when the update adds nothing new.
String extractNewPiece(String update, List<String> existingPieces) {
  final piece = _squash(update);
  if (piece.isEmpty) return '';
  // Longest repeated prefix first (the whole creation), then progressively
  // newer slices of it (e.g. only the newest piece repeated).
  for (var start = 0; start < existingPieces.length; start++) {
    final prefix = _squash(existingPieces.sublist(start).join(' '));
    if (prefix.isEmpty) continue;
    if (piece == prefix) return '';
    if (piece.startsWith('$prefix ')) {
      return piece.substring(prefix.length).trim();
    }
  }
  return piece;
}
