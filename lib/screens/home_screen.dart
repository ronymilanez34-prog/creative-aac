import 'package:flutter/material.dart';

import '../config.dart';
import '../services/companion_factory.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import 'build/build_picture_screen.dart';
import 'build/build_story_screen.dart';
import 'companion_screen.dart';
import 'my_language_screen.dart';
import 'my_stories_screen.dart';
import 'my_words_screen.dart';
import 'partner_screen.dart';

/// Calm landing screen: one clear primary action (build a story) plus access
/// to saved stories. Deliberately sparse to keep it predictable and low-load.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openCompanion(BuildContext context) async {
    // Profile, imported vocabulary and opening topics are all baked in by
    // the shared factory — the same recipe "continue this creation" uses.
    final service = await buildCompanionService();
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompanionScreen(service: service),
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
                    label: 'בואו נבנה תמונה',
                    emoji: '🖼️',
                    color: AppColors.accent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BuildPictureScreen(),
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
                  const SizedBox(height: 16),
                  BigButton(
                    label: 'השפה שלנו',
                    emoji: '🌱',
                    color: AppColors.accent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyLanguageScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Deliberately low-key: the supporter surface, not part of
                  // the user's calm creation flow. Long-press to enter — a
                  // soft gate so a user wandering the home screen doesn't
                  // land in a text-heavy screen that lists their triggers.
                  TextButton.icon(
                    onPressed: () =>
                        ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('לחיצה ארוכה פותחת את מצב המלווה 🔒'),
                      ),
                    ),
                    onLongPress: () => Navigator.of(context).push(
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
                  if (kBuildStamp.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'גרסה $kBuildStamp',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSoft.withValues(alpha: 0.6),
                        ),
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
