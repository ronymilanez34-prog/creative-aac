import 'package:flutter/material.dart';

import '../config.dart';
import '../services/claude_companion_service.dart';
import '../services/companion_service.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import 'build/build_story_screen.dart';
import 'companion_screen.dart';
import 'my_stories_screen.dart';

/// Calm landing screen: one clear primary action (build a story) plus access
/// to saved stories. Deliberately sparse to keep it predictable and low-load.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Real Claude companion when a backend is configured (see lib/config.dart),
  /// otherwise the offline scripted demo — the app always runs.
  CompanionService _companionService() => kCompanionEndpoint.isEmpty
      ? MockCompanionService()
      : ClaudeCompanionService(
          endpoint: kCompanionEndpoint,
          appKey: kCompanionAppKey,
          profileText: kDefaultProfile,
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CompanionScreen(service: _companionService()),
                      ),
                    ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
