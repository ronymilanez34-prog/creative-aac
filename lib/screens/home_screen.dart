import 'package:flutter/material.dart';

import '../config.dart';
import '../services/board_store.dart';
import '../services/claude_companion_service.dart';
import '../services/companion_service.dart';
import '../services/profile_store.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import 'build/build_story_screen.dart';
import 'companion_screen.dart';
import 'my_stories_screen.dart';
import 'my_words_screen.dart';
import 'partner_screen.dart';

/// Calm landing screen: one clear primary action (build a story) plus access
/// to saved stories. Deliberately sparse to keep it predictable and low-load.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Real Claude companion when a backend is configured (see lib/config.dart),
  /// otherwise the offline scripted demo — the app always runs.
  CompanionService _companionService(String profileText) =>
      kCompanionEndpoint.isEmpty
          ? MockCompanionService()
          : ClaudeCompanionService(
              endpoint: kCompanionEndpoint,
              appKey: kCompanionAppKey,
              profileText:
                  profileText.isNotEmpty ? profileText : kDefaultProfile,
            );

  Future<void> _openCompanion(BuildContext context) async {
    // The personal profile (edited in partner mode) feeds the prompt — and so
    // does the vocabulary imported from the user's own AAC board: familiar
    // words are the wide-walls material the AI should offer chips from.
    final profile = await ProfileStore().load();
    final boardWords = await BoardStore().load();
    var promptText = profile.toPromptText();
    if (boardWords.isNotEmpty) {
      final familiar =
          boardWords.take(60).map((w) => w.label).join(', ');
      promptText = '$promptText\n'
              'אוצר המילים המוכר שלו (מהלוח האישי שיובא — העדף להציע מתוכו): '
              '$familiar.'
          .trim();
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompanionScreen(
          service: _companionService(promptText),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Scrollable so short screens (and large text settings) never clip
        // the actions — content stays centered when there is room.
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  const Text('📖✨', style: TextStyle(fontSize: 72)),
                  const SizedBox(height: 16),
                  const Text(
                    'תקשורת חלופית יוצרת',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'בואו ניצור סיפור ביחד',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, color: AppColors.textSoft),
                  ),
                  const SizedBox(height: 40),
                  BigButton(
                    label: 'בואו ניצור ביחד',
                    emoji: '🤖',
                    onTap: () => _openCompanion(context),
                  ),
                  const SizedBox(height: 16),
                  BigButton(
                    label: 'בואו נבנה סיפור',
                    emoji: '🪄',
                    color: AppColors.accent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BuildStoryScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  BigButton(
                    label: 'הסיפורים שלי',
                    emoji: '📚',
                    color: AppColors.accent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyStoriesScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  BigButton(
                    label: 'המילים שלי',
                    emoji: '💬',
                    color: AppColors.accent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyWordsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Deliberately low-key: the supporter surface, not part of
                  // the user's calm creation flow.
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PartnerScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.group_outlined,
                        color: AppColors.textSoft, size: 18),
                    label: const Text(
                      'מצב מלווה',
                      style:
                          TextStyle(color: AppColors.textSoft, fontSize: 15),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
