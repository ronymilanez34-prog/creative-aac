/// The built-in core board: the always-available vocabulary behind the
/// "write it yourself" field, organized the way communication boards are —
/// categories that open into related words. Tapping never requires a
/// keyboard or an imported board; an imported board adds to this, it does
/// not replace it. Core-word selection follows adult AAC practice: high
/// frequency, cross-context words first.

class CoreWord {
  const CoreWord(this.emoji, this.label);

  final String emoji;
  final String label;
}

class CoreCategory {
  const CoreCategory(this.emoji, this.name, this.words);

  final String emoji;
  final String name;
  final List<CoreWord> words;
}

const List<CoreCategory> kCoreVocabulary = [
  CoreCategory('🧑‍🤝‍🧑', 'אנשים', [
    CoreWord('👤', 'אני'),
    CoreWord('🫵', 'אתה'),
    CoreWord('👩', 'אמא'),
    CoreWord('👨', 'אבא'),
    CoreWord('🧑', 'חבר'),
    CoreWord('👩‍🏫', 'מדריכה'),
    CoreWord('👨‍👩‍👧', 'משפחה'),
    CoreWord('🧑‍🤝‍🧑', 'כולם'),
  ]),
  CoreCategory('🏃', 'פעולות', [
    CoreWord('🙋', 'רוצה'),
    CoreWord('🚶', 'הולך'),
    CoreWord('🍽️', 'אוכל'),
    CoreWord('👀', 'רואה'),
    CoreWord('❤️', 'אוהב'),
    CoreWord('🤝', 'עוזר'),
    CoreWord('🎮', 'משחק'),
    CoreWord('🛌', 'נח'),
    CoreWord('🗣️', 'מדבר'),
    CoreWord('🎧', 'שומע'),
  ]),
  CoreCategory('😊', 'רגשות', [
    CoreWord('😊', 'שמח'),
    CoreWord('😢', 'עצוב'),
    CoreWord('😠', 'כועס'),
    CoreWord('🥱', 'עייף'),
    CoreWord('🤩', 'מתרגש'),
    CoreWord('😨', 'מפחד'),
    CoreWord('😌', 'רגוע'),
    CoreWord('🤗', 'אוהב את זה'),
  ]),
  CoreCategory('🏠', 'מקומות', [
    CoreWord('🏠', 'בית'),
    CoreWord('🛏️', 'חדר'),
    CoreWord('🌳', 'בחוץ'),
    CoreWord('🏢', 'עבודה'),
    CoreWord('🌊', 'ים'),
    CoreWord('🏫', 'מועדון'),
    CoreWord('🚌', 'נסיעה'),
    CoreWord('🍽️', 'חדר אוכל'),
  ]),
  CoreCategory('🎲', 'דברים', [
    CoreWord('💧', 'מים'),
    CoreWord('🍞', 'אוכל'),
    CoreWord('🎵', 'מוזיקה'),
    CoreWord('📱', 'טלפון'),
    CoreWord('⚽', 'כדור'),
    CoreWord('📖', 'ספר'),
    CoreWord('🐕', 'כלב'),
    CoreWord('☕', 'קפה'),
  ]),
  CoreCategory('✨', 'איך', [
    CoreWord('🐘', 'גדול'),
    CoreWord('🐭', 'קטן'),
    CoreWord('🌟', 'יפה'),
    CoreWord('💪', 'חזק'),
    CoreWord('🔥', 'חם'),
    CoreWord('🧊', 'קר'),
    CoreWord('⚡', 'מהר'),
    CoreWord('🐌', 'לאט'),
  ]),
  CoreCategory('🕐', 'זמן', [
    CoreWord('👇', 'עכשיו'),
    CoreWord('⏭️', 'אחר כך'),
    CoreWord('📅', 'היום'),
    CoreWord('🌅', 'מחר'),
    CoreWord('🌙', 'לילה'),
    CoreWord('☀️', 'בוקר'),
  ]),
  CoreCategory('🔗', 'מילות חיבור', [
    CoreWord('➕', 'עוד'),
    CoreWord('🤲', 'גם'),
    CoreWord('🚫', 'לא'),
    CoreWord('👍', 'כן'),
    CoreWord('🤝', 'עם'),
    CoreWord('🙅', 'בלי'),
    CoreWord('❓', 'למה'),
    CoreWord('🏁', 'סוף'),
  ]),
];
