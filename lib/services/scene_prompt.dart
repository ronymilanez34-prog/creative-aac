/// The one place that words the prompt sent to the image generator for a
/// scene — shared by the companion loop and the picture builder, so the
/// rule below holds everywhere a picture is painted.
library;

/// Appended to EVERY paint/edit prompt. The generator, like the model,
/// fills gaps with its own ideas: in the field (18.10) a bare "כלב" came
/// back as an old dog by a fireplace at home — none of which the creator
/// chose. The picture is theirs: only what was chosen, and a plain
/// background until a place is chosen.
const String kOnlyWhatWasChosen =
    'צייר רק מה שמתואר: אל תוסיף חפצים, דמויות, מקומות או פעולות שלא '
    'הוזכרו. אם לא מתואר מקום — רקע פשוט וחלק. בלי שום כתב בתמונה: '
    'בלי אותיות, מילים, שמות או מספרים.';

/// The prompt that paints [scene] (the companion's full description).
///
/// [hasBase]: an existing picture rides along as the edit base.
/// [freshPage]: a new page — a new composition that keeps the characters of
/// the previous picture. [stylePrompt]: the chosen style's phrase, or ''.
/// The look of a picture when no style has been chosen yet. The prompt
/// asks the model to put this into scene_update, but a model that forgets
/// hands the generator a bare scene — and the generator's own default is
/// photorealism (field 18.10: a near-photo dog; 16.9: a photo of a
/// stranger instead of "אריק"). So the app always says it.
const String kDefaultSceneStylePrompt =
    'איור מצויר רך וחם, צבעוני ושליו — לא צילום ריאליסטי';

String scenePaintPrompt(
  String scene, {
  required bool hasBase,
  required bool freshPage,
  String stylePrompt = '',
}) {
  final style =
      ' סגנון: ${stylePrompt.isEmpty ? kDefaultSceneStylePrompt : stylePrompt}.';
  if (freshPage) {
    return 'דף חדש בסיפור: צייר סצנה חדשה — $scene. שמור בדיוק על אותן '
        'דמויות כמו בתמונה הקיימת.$style $kOnlyWhatWasChosen';
  }
  if (!hasBase) return '$scene.$style $kOnlyWhatWasChosen';
  // An edit model left to its own devices returns a near-identical picture
  // and quietly skips a small addition (the turtle on the island, 22.9) —
  // say outright that missing things must be added.
  return 'ערוך את התמונה כך שתתאים בדיוק לתיאור: $scene. '
      'הוסף כל דבר מהתיאור שחסר בתמונה, ושמור על מה שכבר '
      'נכון.$style $kOnlyWhatWasChosen';
}
