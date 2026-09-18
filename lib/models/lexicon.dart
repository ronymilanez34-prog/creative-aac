import 'dart:convert';

/// The shared invented language ("רוניקית") — words the creator and the AI
/// coined TOGETHER inside the creation loop, adopted one by one by the
/// creator, and owned by them: viewable, renamable, deletable. This is not
/// the script library (expressions the person already had — see
/// profile.dart); these words were born here, and both sides speak them.
class LexiconWord {
  const LexiconWord({
    required this.word,
    required this.emoji,
    required this.meaning,
    this.origin = '',
    this.createdAtMs = 0,
  });

  /// The invented word itself, in Hebrew letters, exactly as adopted —
  /// spelling is identity, never "corrected".
  final String word;

  /// The symbol that stands for the word (AAC in, AAC out).
  final String emoji;

  /// What the word means, in plain Hebrew — the bridge that lets the
  /// creator open their language to others when THEY choose.
  final String meaning;

  /// Where the word was born (the creation or moment), when known.
  final String origin;

  final int createdAtMs;

  Map<String, dynamic> toJson() => {
        'word': word,
        'emoji': emoji,
        'meaning': meaning,
        'origin': origin,
        'createdAtMs': createdAtMs,
      };

  factory LexiconWord.fromJson(Map<String, dynamic> j) => LexiconWord(
        word: (j['word'] ?? '').toString(),
        emoji: (j['emoji'] ?? '').toString(),
        meaning: (j['meaning'] ?? '').toString(),
        origin: (j['origin'] ?? '').toString(),
        createdAtMs: j['createdAtMs'] is int ? j['createdAtMs'] as int : 0,
      );
}

class Lexicon {
  const Lexicon({this.name = '', this.words = const []});

  /// The language's name — the creator's (e.g. "רוניקית"). Empty until
  /// someone names it; [displayName] covers the gap.
  final String name;

  final List<LexiconWord> words;

  bool get isEmpty => words.isEmpty;

  String get displayName => name.trim().isEmpty ? 'השפה שלנו' : name.trim();

  /// Suggests a name from the person's first name — אריק → אריקית,
  /// רוני → רוניקית. A suggestion only; the creator decides.
  static String suggestName(String personName) {
    final n = personName.trim().split(RegExp(r'\s+')).first;
    if (n.isEmpty) return '';
    return n.endsWith('י') ? '${n}קית' : '${n}ית';
  }

  /// Renders the language block for the companion prompt: adopted words are
  /// real words — the model must speak them, spelled exactly.
  String toPromptText() {
    if (isEmpty) return '';
    final b = StringBuffer();
    b.writeln('השפה המשותפת שלכם — «$displayName» — מילים שהומצאו ואומצו '
        'יחד ביצירה. אלה מילים אמיתיות של שניכם: השתמש בהן כלשונן (בכתיב '
        'מדויק) בשיחה, ביצירה, בסמלים ובאפשרויות:');
    for (final w in words) {
      final origin = w.origin.trim().isEmpty ? '' : ' (נולדה: ${w.origin})';
      b.writeln('- «${w.word}» ${w.emoji} = ${w.meaning}$origin');
    }
    return b.toString().trim();
  }

  Lexicon copyWith({String? name, List<LexiconWord>? words}) =>
      Lexicon(name: name ?? this.name, words: words ?? this.words);

  Map<String, dynamic> toJson() => {
        'name': name,
        'words': words.map((w) => w.toJson()).toList(),
      };

  factory Lexicon.fromJson(Map<String, dynamic> j) => Lexicon(
        name: (j['name'] ?? '').toString(),
        words: (j['words'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LexiconWord.fromJson)
            .where((w) => w.word.trim().isNotEmpty)
            .toList(),
      );

  String encode() => jsonEncode(toJson());

  factory Lexicon.decode(String raw) {
    // A corrupt stored lexicon must never take down the creation flow —
    // any failure falls back to an empty language (same rule as the
    // profile).
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return Lexicon.fromJson(j);
    } catch (_) {
      // fall through to empty lexicon
    }
    return const Lexicon();
  }
}
