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
