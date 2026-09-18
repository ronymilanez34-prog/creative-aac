import '../config.dart';
import 'board_store.dart';
import 'claude_companion_service.dart';
import 'companion_service.dart';
import 'lexicon_store.dart';
import 'profile_store.dart';

/// The one recipe for a companion service, used by every door into the
/// creation loop (home, and "continue this creation" from a saved story):
/// the personal profile and the vocabulary imported from the user's own AAC
/// board are baked into the prompt — familiar words are the wide-walls
/// material the AI offers topics from once a creation type is chosen.
Future<CompanionService> buildCompanionService() async {
  final profile = await ProfileStore().load();
  final boardWords = await BoardStore().load();
  final lexicon = await LexiconStore().load();
  var promptText = profile.toPromptText();
  if (!lexicon.isEmpty) {
    // The shared invented language: adopted words are real words of both
    // sides — the model must speak them (a word adopted mid-session reaches
    // the model through the conversation history until the next session
    // bakes it in here).
    promptText = '$promptText\n${lexicon.toPromptText()}'.trim();
  }
  if (boardWords.isNotEmpty) {
    // A button's spoken text often carries the MEANING behind a private
    // name ("צ'יקו" speaks as "צ'יקו הכלב שלי") — ride it along so the
    // model knows who Chiko is, not only that the word exists.
    final familiar = boardWords.take(60).map((w) {
      final speak = w.speak?.trim() ?? '';
      return speak.isNotEmpty && speak != w.label
          ? '${w.label} (במילותיו: $speak)'
          : w.label;
    }).join(', ');
    promptText = '$promptText\n'
            'אוצר המילים המוכר שלו (מהלוח האישי שיובא — העדף להציע מתוכו): '
            '$familiar.'
        .trim();
  }
  return kCompanionEndpoint.isEmpty
      ? MockCompanionService()
      : ClaudeCompanionService(
          endpoint: kCompanionEndpoint,
          appKey: kCompanionAppKey,
          profileText: promptText.isNotEmpty ? promptText : kDefaultProfile,
        );
}
