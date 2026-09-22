import '../models/lexicon.dart';

/// The in-memory map from an adopted word to its owner's recorded voice.
///
/// Kept fresh by LexiconStore on every load/save, and consulted by
/// Speech.speak: when a spoken text IS exactly one adopted word that has a
/// recording, the creator's own voice plays instead of TTS — everywhere in
/// the app (a chip in the creation loop, the word card, the adoption
/// moment), with no screen needing to know. Sentences never match; only
/// the word alone is the word's sound.
class VoiceRegistry {
  VoiceRegistry._();

  static Map<String, String> _byWord = const {};

  static void update(Lexicon lexicon) {
    _byWord = {
      for (final w in lexicon.words)
        if (w.hasVoice && w.word.trim().isNotEmpty) w.word.trim(): w.voice,
    };
  }

  /// The recorded voice for [text], when the text is that word alone —
  /// allowing the wrapping the UI and prompt put around words («מילה»,
  /// trailing punctuation), or null to fall through to TTS.
  static String? lookup(String text) {
    if (_byWord.isEmpty) return null;
    final t = _strip(text);
    if (t.isEmpty) return null;
    return _byWord[t];
  }

  static const _trimmable = '«»"\'’׳ \t\n.!?,:;';

  static String _strip(String text) {
    final t = text.trim();
    var start = 0;
    var end = t.length;
    while (start < end && _trimmable.contains(t[start])) {
      start++;
    }
    while (end > start && _trimmable.contains(t[end - 1])) {
      end--;
    }
    return t.substring(start, end);
  }
}
