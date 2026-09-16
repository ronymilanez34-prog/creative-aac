import '../config.dart';
import 'board_store.dart';
import 'claude_companion_service.dart';
import 'companion_service.dart';
import 'profile_store.dart';

/// The one recipe for a companion service, used by every door into the
/// creation loop (home, and "continue this creation" from a saved story):
/// the personal profile and the vocabulary imported from the user's own AAC
/// board are baked into the prompt — familiar words are the wide-walls
/// material the AI should offer chips from — and the user's favourite
/// topics become opening chips, so the very first choice can already be
/// THEIR world, not only a creation type.
Future<CompanionService> buildCompanionService() async {
  final profile = await ProfileStore().load();
  final boardWords = await BoardStore().load();
  var promptText = profile.toPromptText();
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
  // Personal topics for the opening chips: loved things first, then the
  // first imported board words — deduped, a handful at most.
  final topics = <String>[];
  for (final t in [
    ...profile.loves,
    ...boardWords.map((w) => w.label),
  ]) {
    final label = t.trim();
    if (label.isNotEmpty && !topics.contains(label)) topics.add(label);
    if (topics.length >= 3) break;
  }
  return kCompanionEndpoint.isEmpty
      ? MockCompanionService()
      : ClaudeCompanionService(
          endpoint: kCompanionEndpoint,
          appKey: kCompanionAppKey,
          profileText: promptText.isNotEmpty ? promptText : kDefaultProfile,
          openingTopics: topics,
        );
}
