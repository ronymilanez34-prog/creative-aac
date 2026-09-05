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

/// One level of narrative continuity: after an event, the next options
/// continue THAT thread instead of resetting to the generic list. Every label
/// is a hero-subject verb phrase, so the page template stays uniform
/// ('ואז ‹גיבור› ‹label›!'). After a follow-up the generic list returns.
const Map<String, List<Choice>> kFollowUps = {
  'treasure': [
    Choice(id: 'treasure_open', label: 'פתח את האוצר', emoji: '🔓'),
    Choice(id: 'treasure_share', label: 'חילק לכולם', emoji: '🤲'),
    Choice(id: 'treasure_hide', label: 'שמר אותו בסוד', emoji: '🤫'),
  ],
  'friend': [
    Choice(id: 'friend_play', label: 'שיחק עם החבר', emoji: '🎲'),
    Choice(id: 'friend_walk', label: 'יצא איתו לטיול', emoji: '🚶'),
    Choice(id: 'friend_laugh', label: 'צחק איתו המון', emoji: '😄'),
  ],
  'adventure': [
    Choice(id: 'adventure_mountain', label: 'טיפס על הר', emoji: '⛰️'),
    Choice(id: 'adventure_river', label: 'חצה נהר', emoji: '🛶'),
    Choice(id: 'adventure_cave', label: 'מצא מערה', emoji: '🕳️'),
  ],
  'rescue': [
    Choice(id: 'rescue_thanks', label: 'קיבל תודה ענקית', emoji: '💝'),
    Choice(id: 'rescue_hero', label: 'הרגיש גיבור', emoji: '🦸'),
    Choice(id: 'rescue_hug', label: 'חיבק את כולם', emoji: '🤗'),
  ],
  'secret': [
    Choice(id: 'secret_tell', label: 'סיפר לחבר', emoji: '🗣️'),
    Choice(id: 'secret_keep', label: 'שמר על הסוד', emoji: '🤫'),
    Choice(id: 'secret_follow', label: 'הלך בעקבות הסוד', emoji: '🧭'),
  ],
  'party': [
    Choice(id: 'party_dance', label: 'רקד עם כולם', emoji: '💃'),
    Choice(id: 'party_cake', label: 'אכל עוגה', emoji: '🎂'),
    Choice(id: 'party_sing', label: 'שר שירים', emoji: '🎤'),
  ],
  'journey': [
    Choice(id: 'journey_places', label: 'ראה מקומות חדשים', emoji: '🌍'),
    Choice(id: 'journey_postcard', label: 'שלח גלויה הביתה', emoji: '💌'),
    Choice(id: 'journey_gifts', label: 'חזר עם מתנות', emoji: '🎁'),
  ],
};
