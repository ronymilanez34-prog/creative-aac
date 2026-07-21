import '../models/story.dart';

/// Turns a [StorySpec] (the user's choices) into a finished [Story].
///
/// This is the seam where "generative AAC" lives. Today it ships with a fully
/// offline [LocalTemplateStoryGenerator] so the app runs with no setup. Later,
/// swap in an AI-backed generator (see [ClaudeStoryGenerator]) for richer,
/// truly generative co-creation — without changing any UI code.
abstract class StoryGenerator {
  Future<Story> generate(StorySpec spec);
}

/// Offline, deterministic story builder. No API key, no network — the app is
/// fully usable out of the box. Grammar is intentionally simple and warm.
class LocalTemplateStoryGenerator implements StoryGenerator {
  const LocalTemplateStoryGenerator();

  @override
  Future<Story> generate(StorySpec spec) async {
    final hero = spec.hero!;
    final place = spec.place!;
    final event = spec.event!;

    final title = '${hero.label} ${place.label}';

    final pages = <StoryPage>[
      StoryPage(
        emoji: hero.emoji,
        text: 'היֹה היה ${hero.label}. כל בוקר ${hero.label} התעורר עם חיוך גדול.',
      ),
      StoryPage(
        emoji: place.emoji,
        text: 'יום אחד ${hero.label} הגיע ${place.label}. הכול שם היה חדש ומעניין.',
      ),
      StoryPage(
        emoji: event.emoji,
        text: 'ואז קרה משהו מיוחד: ${hero.label} ${event.label}!',
      ),
    ];

    final idea = spec.customIdea?.trim();
    if (idea != null && idea.isNotEmpty) {
      pages.add(StoryPage(emoji: '💡', text: idea));
    }

    pages.add(const StoryPage(
      emoji: '🌟',
      text: 'זה היה יום נהדר. הסוף.',
    ));

    final now = DateTime.now();
    return Story(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      pages: pages,
      createdAtMs: now.millisecondsSinceEpoch,
    );
  }
}

/// AI-backed generator — the next step toward true generative AAC.
///
/// NOT wired up by default. Two important notes before enabling it:
///
///  1. Do NOT ship an API key inside the app. Route requests through a small
///     backend (e.g. a Cloud Function) that holds the key server-side.
///  2. The prompt should ask for a short, warm, age-appropriate story split
///     into a few short "pages", returned as structured JSON so it maps
///     cleanly onto [StoryPage]s.
///
/// Left here as a documented placeholder so the architecture is ready.
class ClaudeStoryGenerator implements StoryGenerator {
  const ClaudeStoryGenerator();

  @override
  Future<Story> generate(StorySpec spec) {
    throw UnimplementedError(
      'AI generation not wired yet — see README for the planned backend flow.',
    );
  }
}
