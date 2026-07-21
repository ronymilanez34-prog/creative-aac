import '../models/story.dart';

/// The building blocks the user picks from. Emoji-based so the app needs no
/// image assets and stays visual and low-text.
///
/// To add options, just add entries here — the UI adapts automatically.

const List<Choice> kHeroes = [
  Choice(id: 'girl', label: 'ילדה', emoji: '👧'),
  Choice(id: 'boy', label: 'ילד', emoji: '👦'),
  Choice(id: 'dog', label: 'כלב', emoji: '🐶'),
  Choice(id: 'cat', label: 'חתול', emoji: '🐱'),
  Choice(id: 'dragon', label: 'דרקון', emoji: '🐉'),
  Choice(id: 'robot', label: 'רובוט', emoji: '🤖'),
  Choice(id: 'lion', label: 'אריה', emoji: '🦁'),
  Choice(id: 'astronaut', label: 'אסטרונאוט', emoji: '👩‍🚀'),
  Choice(id: 'bear', label: 'דוב', emoji: '🐻'),
];

const List<Choice> kPlaces = [
  Choice(id: 'forest', label: 'ביער', emoji: '🌳'),
  Choice(id: 'sea', label: 'בים', emoji: '🌊'),
  Choice(id: 'space', label: 'בחלל', emoji: '🚀'),
  Choice(id: 'castle', label: 'בטירה', emoji: '🏰'),
  Choice(id: 'park', label: 'בגן השעשועים', emoji: '🎠'),
  Choice(id: 'home', label: 'בבית', emoji: '🏠'),
  Choice(id: 'mountain', label: 'בהר', emoji: '⛰️'),
  Choice(id: 'island', label: 'באי', emoji: '🏝️'),
];

const List<Choice> kEvents = [
  Choice(id: 'treasure', label: 'מצא אוצר', emoji: '💎'),
  Choice(id: 'friend', label: 'פגש חבר חדש', emoji: '🤝'),
  Choice(id: 'adventure', label: 'יצא להרפתקה', emoji: '🧭'),
  Choice(id: 'rescue', label: 'הציל מישהו', emoji: '🦸'),
  Choice(id: 'secret', label: 'גילה סוד', emoji: '🔑'),
  Choice(id: 'party', label: 'ערך מסיבה', emoji: '🎉'),
  Choice(id: 'journey', label: 'נסע רחוק', emoji: '🚂'),
];
