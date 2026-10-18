/// The picture styles the creator can pick — one shared vocabulary for
/// every place a scene gets painted (the companion loop; the standalone
/// picture builder keeps a private copy until it migrates here).
library;

class SceneStyle {
  const SceneStyle(this.emoji, this.name, this.prompt);

  final String emoji;
  final String name;

  /// The style phrase sent to the image generator.
  final String prompt;
}

const kSceneStyles = [
  SceneStyle('🎨', 'ציור רך', 'איור דיגיטלי רך, צבעוני ושליו'),
  SceneStyle('📷', 'כמו צילום', 'צילום מציאותי, יפה ומואר'),
  SceneStyle('🖍️', 'ציור ילדים', 'ציור עליז בצבעי עפרון, פשוט ושמח'),
  SceneStyle('💥', 'קומיקס', 'קומיקס צבעוני עם קווים ברורים'),
  SceneStyle('🌊', 'צבעי מים', 'ציור עדין ורגוע בצבעי מים'),
  SceneStyle('👾', 'משחק', 'פיקסל ארט צבעוני של משחק מחשב'),
];

/// The style a tapped label names, or null when the label is content.
/// Accepts the bare name and the emoji-prefixed form the style question
/// shows ("🎨 ציור רך") — one vocabulary wherever a style is chosen.
SceneStyle? styleFromLabel(String label) {
  final t = label.trim();
  for (final s in kSceneStyles) {
    if (t == s.name || t == '${s.emoji} ${s.name}') return s;
  }
  return null;
}

/// The one style question the app asks itself, once per creation, right
/// after the first picture — spoken whole, six big choices (field 18.10:
/// the model was told to ask and never did; a question the app asks is
/// predictable).
const String kStyleQuestion = 'באיזה סגנון נצייר?';
List<String> get kStyleQuestionOptions =>
    [for (final s in kSceneStyles) '${s.emoji} ${s.name}'];

/// The app's own "new page?" question after the model flags a scene
/// change (a new place or time). The creator decides; the two answers
/// are app vocabulary, never content.
const String kNewPageQuestion = 'זה מקום חדש. לפתוח דף חדש?';
const String kNewPageYes = '📄 דף חדש';
const String kNewPageNo = 'להמשיך באותו דף';
