import 'package:flutter/material.dart';

import '../models/story.dart';
import '../services/speech.dart';
import '../services/story_store.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// Reads a finished [Story] one page at a time, with big picture + text and a
/// read-aloud button. The user controls the pace with clear next/back arrows.
class StoryViewScreen extends StatefulWidget {
  const StoryViewScreen({super.key, required this.story});

  final Story story;

  @override
  State<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends State<StoryViewScreen> {
  final PageController _controller = PageController();
  final Speech _speech = Speech();
  final StoryStore _store = StoryStore();
  int _page = 0;
  bool _saved = false;

  /// Shared re-reading mode: shows each page's saved questions as
  /// conversation prompts (the partner asks, waits — every answer counts).
  /// Available only when the story carries questions.
  bool _reReading = false;

  bool get _hasQuestions =>
      widget.story.pages.any((p) => p.questions.isNotEmpty);

  @override
  void dispose() {
    _controller.dispose();
    _speech.dispose();
    super.dispose();
  }

  void _speakCurrent() => _speech.speak(widget.story.pages[_page].text);

  Future<void> _readWholeStory() async {
    final all = widget.story.pages.map((p) => p.text).join(' ');
    await _speech.speak(all);
  }

  Future<void> _save() async {
    await _store.save(widget.story);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הסיפור נשמר 📚')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.story.pages;
    final isLast = _page == pages.length - 1;
    final isFirst = _page == 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.story.title),
        actions: [
          if (_hasQuestions)
            IconButton(
              tooltip: _reReading ? 'סגירת קריאה חוזרת' : 'קריאה חוזרת (עם שאלות)',
              icon: Icon(
                _reReading ? Icons.menu_book : Icons.menu_book_outlined,
              ),
              onPressed: () => setState(() => _reReading = !_reReading),
            ),
          IconButton(
            tooltip: 'הקרא את כל הסיפור',
            icon: const Icon(Icons.record_voice_over),
            onPressed: _readWholeStory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: pages.length,
              itemBuilder: (context, i) {
                final p = pages[i];
                final showQuestions = _reReading && p.questions.isNotEmpty;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(p.emoji,
                          style: TextStyle(fontSize: showQuestions ? 72 : 120)),
                      const SizedBox(height: 24),
                      Text(
                        p.text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      if (showQuestions) ...[
                        const SizedBox(height: 24),
                        for (final q in p.questions)
                          _QuestionCard(
                            question: q,
                            onSpeak: () => _speech.speak(q),
                          ),
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'שאלו, חכו בסבלנות — וכל תשובה היא תשובה טובה.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSoft,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          _Dots(count: pages.length, active: _page),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _CircleIcon(
                  icon: Icons.chevron_right, // RTL: previous
                  enabled: !isFirst,
                  onTap: () => _controller.previousPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BigButton(
                    label: 'הקרא',
                    emoji: '🔊',
                    onTap: _speakCurrent,
                  ),
                ),
                const SizedBox(width: 12),
                _CircleIcon(
                  icon: Icons.chevron_left, // RTL: next
                  enabled: !isLast,
                  onTap: () => _controller.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: BigButton(
                      label: _saved ? 'נשמר ✓' : 'שמור סיפור',
                      emoji: _saved ? null : '💾',
                      color: _saved ? AppColors.textSoft : AppColors.accent,
                      enabled: !_saved,
                      onTap: _save,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BigButton(
                      label: 'סיפור חדש',
                      emoji: '🪄',
                      color: AppColors.primaryDark,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.onSpeak});

  final String question;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              question,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          IconButton(
            tooltip: 'הקרא את השאלה',
            icon: const Icon(Icons.volume_up_rounded, color: AppColors.accent),
            onPressed: onSpeak,
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: on ? 14 : 10,
          height: on ? 14 : 10,
          decoration: BoxDecoration(
            color: on ? AppColors.primary : AppColors.border,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.primary : AppColors.border,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
