/// Core data model for the story-building flow.
///
/// A [Choice] is one selectable option (hero / place / event). A [StorySpec]
/// collects the user's choices. A [Story] is the finished result — a list of
/// [StoryPage]s that can be read on screen and spoken aloud.
library;

class Choice {
  const Choice({required this.id, required this.label, required this.emoji});

  final String id;
  final String label;
  final String emoji;
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
  const StoryPage({
    required this.text,
    required this.emoji,
    this.questions = const [],
    this.imageB64,
  });

  final String text;
  final String emoji;

  /// Simple comprehension questions about this page, generated at creation
  /// time — the material for the shared re-reading mode (the partner asks,
  /// waits, and every answer is a good answer).
  final List<String> questions;

  /// The REAL picture the user made (base64, already shrunk for storage).
  /// A creation must never vanish — the painted lion of today is the thing
  /// they open tomorrow and show. Null for text-only pages.
  final String? imageB64;

  Map<String, dynamic> toJson() => {
        'text': text,
        'emoji': emoji,
        if (questions.isNotEmpty) 'questions': questions,
        if (imageB64 != null) 'imageB64': imageB64,
      };

  factory StoryPage.fromJson(Map<String, dynamic> j) => StoryPage(
        text: j['text'] as String,
        emoji: j['emoji'] as String,
        questions: (j['questions'] as List? ?? const [])
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(),
        imageB64: j['imageB64'] as String?,
      );

  StoryPage withoutImage() =>
      StoryPage(text: text, emoji: emoji, questions: questions);
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

  /// The same story with pictures stripped — the storage-full fallback:
  /// losing a picture is bad, losing the whole creation is worse.
  Story withoutImages() => Story(
        id: id,
        title: title,
        createdAtMs: createdAtMs,
        pages: pages.map((p) => p.withoutImage()).toList(),
      );
}
