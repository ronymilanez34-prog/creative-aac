import 'package:shared_preferences/shared_preferences.dart';

import '../models/lexicon.dart';
import 'voice_registry.dart';

/// On-device storage for the shared invented language. Lives in
/// SharedPreferences like the profile, so the full backup (backup.dart)
/// carries it automatically — a language must survive a cleared browser.
class LexiconStore {
  static const _key = 'lexicon_v1';

  Future<Lexicon> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final lexicon = (raw == null || raw.isEmpty)
        ? const Lexicon()
        : Lexicon.decode(raw);
    // Every load refreshes the voice map Speech consults — the words'
    // recorded voices follow the stored language wherever it goes
    // (including a restored backup).
    VoiceRegistry.update(lexicon);
    return lexicon;
  }

  Future<void> save(Lexicon lexicon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lexicon.encode());
    VoiceRegistry.update(lexicon);
  }

  /// Adopts one word into the language. Same spelling already there →
  /// the existing entry stays (first adoption wins; identity over update).
  /// Returns the lexicon as stored after the call.
  Future<Lexicon> adopt(LexiconWord word) async {
    final current = await load();
    if (current.words.any((w) => w.word.trim() == word.word.trim())) {
      return current;
    }
    final next = current.copyWith(words: [...current.words, word]);
    await save(next);
    return next;
  }

  /// Removes a word — the creator's "no" stays cheap, also about their
  /// own language. Returns the lexicon as stored after the call.
  Future<Lexicon> remove(String word) async {
    final current = await load();
    final next = current.copyWith(
      words: current.words.where((w) => w.word != word).toList(),
    );
    await save(next);
    return next;
  }

  /// Attaches (or, with an empty [voice], removes) the creator's recorded
  /// voice on one word. Returns the lexicon as stored after the call.
  Future<Lexicon> setVoice(String word, String voice) async {
    final current = await load();
    final next = current.copyWith(words: [
      for (final w in current.words)
        w.word == word ? w.copyWith(voice: voice) : w,
    ]);
    await save(next);
    return next;
  }

  /// Renames the language itself (רוניקית, אריקית...).
  Future<Lexicon> rename(String name) async {
    final current = await load();
    final next = current.copyWith(name: name.trim());
    await save(next);
    return next;
  }
}
