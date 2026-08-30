/// Core data model for the story-building flow.
///
/// A [Choice] is one selectable option (hero / place / event). A [StorySpec]
/// collects the user's choices. A [Story] is the finished result — a list of
/// [StoryPage]s that can be read on screen and spoken aloud.

class Choice {
  const Choice({
    required this.id,
    required this.label,
    required this.emoji,
    this.imagePath,
  });

  final String id;
  final String label;
  final String emoji;

  /// Absolute path to an image from the user's imported board — when set,
  /// the UI shows the familiar picture instead of the emoji.
  final String? imagePath;
}

/// The user's in-progress selections while building a story.
class StorySpec {
  Choice? hero;
  Choice? place;
  Choice? event;

  /// Optional free-text idea for users who can and want to type. Kept optional
  /// on purpose — the core flow is choice-based to keep cognitive load low.
  String? customIdea;

  bool get isComplete => hero != null && place != null && event != null;
}

class StoryPage {
  const StoryPage({required this.text, required this.emoji});

  final String text;
  final String emoji;

  Map<String, dynamic> toJson() => {'text': text, 'emoji': emoji};

  factory StoryPage.fromJson(Map<String, dynamic> j) =>
      StoryPage(text: j['text'] as String, emoji: j['emoji'] as String);
}

class Story {
  const Story({
    required this.id,
    required this.title,
    required this.pages,
    required this.createdAtMs,
  });

  final String id;
  final String title;
  final List<StoryPage> pages;
  final int createdAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAtMs': createdAtMs,
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory Story.fromJson(Map<String, dynamic> j) => Story(
        id: j['id'] as String,
        title: j['title'] as String,
        createdAtMs: j['createdAtMs'] as int,
        pages: (j['pages'] as List)
            .map((e) => StoryPage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
