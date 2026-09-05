/// Data model for one turn of the companion (supported free conversation).
/// Mirrors the JSON output contract in docs/prompts/companion_system_prompt.md.
library;

class ChipOption {
  const ChipOption({required this.emoji, required this.label});

  final String emoji;
  final String label;

  factory ChipOption.fromJson(Map<String, dynamic> j) => ChipOption(
        emoji: (j['emoji'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
      );
}

class ConfirmPrompt {
  const ConfirmPrompt({required this.question, required this.options});

  final String question;
  final List<String> options;

  factory ConfirmPrompt.fromJson(Map<String, dynamic> j) => ConfirmPrompt(
        question: (j['question'] ?? '').toString(),
        options:
            (j['options'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
}

/// Who produced a piece of input this turn. A partner's modelling tap is never
/// the user's own expression — the distinction is kept end-to-end (prompt,
/// log, provenance).
enum InputSource { user, partner }

/// One unit of the companion's message rendered in AAC: symbol + word.
/// "AAC in, AAC out" — whoever communicates in symbols gets answered in
/// symbols (aided language input); the full [CompanionTurn.say] stays for TTS.
class SaySymbol {
  const SaySymbol({required this.emoji, required this.word});

  final String emoji;
  final String word;

  factory SaySymbol.fromJson(Map<String, dynamic> j) => SaySymbol(
        emoji: (j['emoji'] ?? '').toString(),
        word: (j['word'] ?? '').toString(),
      );
}

class CompanionTurn {
  const CompanionTurn({
    required this.say,
    this.saySymbols = const [],
    this.creationUpdate,
    this.needsConfirmation = false,
    this.confirm,
    this.options = const [],
    this.partnerTip,
    this.questions = const [],
    this.safeguard = false,
  });

  /// Short warm response — spoken aloud (and the fallback when no symbols).
  final String say;

  /// The same message as a telegraphic symbol sequence — what the eyes read.
  final List<SaySymbol> saySymbols;

  /// New piece appended to the creation (or null).
  final String? creationUpdate;

  /// When true, show the [confirm] prompt instead of advancing —
  /// the "confirmation, not silent decision" mechanic.
  final bool needsConfirmation;
  final ConfirmPrompt? confirm;

  /// 3-4 tappable next options.
  final List<ChipOption> options;

  /// Short coaching hint for a communication partner sitting alongside —
  /// shown only in partner mode, never to the user.
  final String? partnerTip;

  /// 1-2 simple comprehension questions about [creationUpdate], kept for the
  /// re-reading mode of the finished creation.
  final List<String> questions;

  /// When true, the app alerts a human (facilitator/clinician) and does not
  /// continue as usual.
  final bool safeguard;

  factory CompanionTurn.fromJson(Map<String, dynamic> j) => CompanionTurn(
        say: (j['say'] ?? '').toString(),
        saySymbols: (j['say_symbols'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SaySymbol.fromJson)
            .where((s) => s.word.trim().isNotEmpty)
            .toList(),
        creationUpdate: j['creation_update']?.toString(),
        needsConfirmation: j['needs_confirmation'] == true,
        confirm: j['confirm'] is Map<String, dynamic>
            ? ConfirmPrompt.fromJson(j['confirm'] as Map<String, dynamic>)
            : null,
        options: (j['options'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChipOption.fromJson)
            .toList(),
        partnerTip: j['partner_tip']?.toString(),
        questions: (j['questions'] as List? ?? const [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(),
        safeguard: j['safeguard'] == true,
      );
}

/// One piece of the growing creation, with provenance: the AI text plus the
/// user input that triggered it. This is the raw material for "show what I
/// chose" views and for demonstrable authorship.
class CreationPiece {
  const CreationPiece({
    required this.text,
    required this.userInput,
    required this.source,
    this.questions = const [],
  });

  /// The text the AI appended to the creation.
  final String text;

  /// What the user (or partner) actually selected/typed this turn.
  final String userInput;

  final InputSource source;

  /// Simple comprehension questions about [text], kept for the re-reading
  /// mode of the finished creation.
  final List<String> questions;
}
