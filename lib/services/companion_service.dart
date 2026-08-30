import '../models/board.dart';
import '../models/companion.dart';

/// Produces companion turns. The UI depends only on this interface, so the
/// mock (demo) and the real Claude-backed implementation are interchangeable.
abstract class CompanionService {
  /// The very first message, before the user has said anything.
  CompanionTurn opening();

  /// One turn: given the user's latest input, return the companion's response.
  Future<CompanionTurn> turn(String userInput);
}

/// Offline, scripted companion for the demo. No API key, no network — runs
/// instantly anywhere, so the concept can be shown at ALUT today.
///
/// The script walks a short story-building arc that deliberately demonstrates
/// the key ideas: supported options + free input, celebrating the user's own
/// words, and the "confirmation, not silent decision" mechanic.
class MockCompanionService implements CompanionService {
  MockCompanionService({List<BoardWord> vocabulary = const []})
      : _vocabulary = vocabulary;

  /// The user's own words, imported from their AAC board. When present, the
  /// companion offers THESE as options — familiar words with familiar
  /// pictures — instead of our generic defaults.
  final List<BoardWord> _vocabulary;

  int _step = 0;

  /// Up to [count] vocabulary words starting at [from], as tappable chips.
  List<ChipOption> _vocabChips(int from, int count) => _vocabulary
      .skip(from)
      .take(count)
      .map((w) => ChipOption(emoji: '💬', label: w.label, imagePath: w.imagePath))
      .toList();

  @override
  CompanionTurn opening() {
    final vocab = _vocabChips(0, 3);
    return CompanionTurn(
      say: 'היי! בוא ניצור סיפור ביחד 🙂 על מה בא לך?',
      options: [
        if (vocab.isNotEmpty)
          ...vocab
        else ...const [
          ChipOption(emoji: '🐶', label: 'כלב'),
          ChipOption(emoji: '🚀', label: 'חלל'),
          ChipOption(emoji: '⚽', label: 'כדורגל'),
        ],
        const ChipOption(emoji: '❓', label: 'משהו אחר'),
      ],
    );
  }

  @override
  Future<CompanionTurn> turn(String userInput) async {
    // Small delay so the demo feels like a real response.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final input = userInput.trim();
    _step++;

    switch (_step) {
      case 1:
        return CompanionTurn(
          say: 'וואו, $input! נשמע התחלה מעולה. איפה הסיפור קורה?',
          creationUpdate: 'היה היה $input.',
          options: const [
            ChipOption(emoji: '🌳', label: 'ביער'),
            ChipOption(emoji: '🏠', label: 'בבית'),
            ChipOption(emoji: '🌊', label: 'בים'),
            ChipOption(emoji: '❓', label: 'משהו אחר'),
          ],
        );

      case 2:
        // Demonstrate the confirmation mechanic (interpret, don't decide).
        return CompanionTurn(
          say: 'רגע, שאבין נכון —',
          needsConfirmation: true,
          confirm: ConfirmPrompt(
            question: 'התכוונת ש-$input זה מקום שמח, או מקום קצת מפחיד?',
            options: const ['מקום שמח 😊', 'קצת מפחיד 😨'],
          ),
        );

      case 3:
        final moreVocab = _vocabChips(3, 3);
        return CompanionTurn(
          say: 'מושלם, הבנתי. ומי עוד נמצא שם איתו?',
          creationUpdate: 'הוא הגיע $input, וזה היה בדיוק המקום בשבילו.',
          options: [
            if (moreVocab.isNotEmpty)
              ...moreVocab
            else ...const [
              ChipOption(emoji: '👧', label: 'חברה'),
              ChipOption(emoji: '👵', label: 'סבתא'),
              ChipOption(emoji: '🐱', label: 'חתול'),
            ],
            const ChipOption(emoji: '❓', label: 'משהו אחר'),
          ],
        );

      case 4:
        return CompanionTurn(
          say: 'איזה יופי — $input! ורוצה שיקרה משהו מיוחד?',
          creationUpdate: 'ואז הגיע/ה $input, והם שמחו להיפגש.',
          options: const [
            ChipOption(emoji: '💎', label: 'מצאו אוצר'),
            ChipOption(emoji: '🎉', label: 'עשו מסיבה'),
            ChipOption(emoji: '🎈', label: 'טסו באוויר'),
            ChipOption(emoji: '❓', label: 'משהו אחר'),
          ],
        );

      default:
        return CompanionTurn(
          say: 'איזה סיפור יפה יצרת! 🌟 רוצה לשמוע אותו מההתחלה, או להתחיל חדש?',
          creationUpdate: 'וכך, $input. וזה היה יום נהדר. הסוף. 🌟',
          options: const [
            ChipOption(emoji: '🔊', label: 'קרא הכל'),
            ChipOption(emoji: '🪄', label: 'סיפור חדש'),
          ],
        );
    }
  }
}
