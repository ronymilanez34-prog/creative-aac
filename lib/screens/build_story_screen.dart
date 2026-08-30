import 'package:flutter/material.dart';

import '../data/choices.dart';
import '../models/board.dart';
import '../models/story.dart';
import '../services/board_store.dart';
import '../services/story_generator.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/choice_card.dart';
import 'story_view_screen.dart';

/// The guided story-building flow: three simple steps (hero → place → event),
/// each a grid of big picture cards, then the finished story opens in
/// [StoryViewScreen].
///
/// When the user has imported their own board ("המילים שלי"), those words —
/// with their familiar pictures — are offered as heroes alongside the
/// built-in options.
class BuildStoryScreen extends StatefulWidget {
  const BuildStoryScreen({super.key});

  @override
  State<BuildStoryScreen> createState() => _BuildStoryScreenState();
}

class _BuildStoryScreenState extends State<BuildStoryScreen> {
  final StorySpec _spec = StorySpec();
  final StoryGenerator _generator = const LocalTemplateStoryGenerator();

  int _step = 0;
  bool _generating = false;
  List<Choice> _heroes = kHeroes;

  static const _titles = ['מי הגיבור?', 'איפה זה קורה?', 'מה קורה בסיפור?'];
  static const _emojis = ['🦸', '🗺️', '✨'];

  @override
  void initState() {
    super.initState();
    _loadImportedWords();
  }

  /// The user's own imported words become hero options, shown FIRST — a story
  /// about someone you know beats a story about a generic dragon.
  Future<void> _loadImportedWords() async {
    final words = await BoardStore().load();
    if (!mounted || words.isEmpty) return;
    final imported = words
        .take(12)
        .map((BoardWord w) => Choice(
              id: 'board_${w.id}',
              label: w.label,
              emoji: '💬',
              imagePath: w.imagePath,
            ))
        .toList();
    setState(() => _heroes = [...imported, ...kHeroes]);
  }

  List<Choice> get _options => switch (_step) {
        0 => _heroes,
        1 => kPlaces,
        _ => kEvents,
      };

  Choice? get _selected => switch (_step) {
        0 => _spec.hero,
        1 => _spec.place,
        _ => _spec.event,
      };

  void _select(Choice c) {
    setState(() {
      switch (_step) {
        case 0:
          _spec.hero = c;
        case 1:
          _spec.place = c;
        default:
          _spec.event = c;
      }
    });
  }

  Future<void> _next() async {
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    if (!_spec.isComplete || _generating) return;
    setState(() => _generating = true);
    final story = await _generator.generate(_spec);
    if (!mounted) return;
    setState(() => _generating = false);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => StoryViewScreen(story: story)),
    );
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _step == 2;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_emojis[_step]} ${_titles[_step]}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _back,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _StepDots(active: _step),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _options.length,
                itemBuilder: (context, i) {
                  final c = _options[i];
                  return ChoiceCard(
                    choice: c,
                    selected: _selected?.id == c.id,
                    onTap: () => _select(c),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _generating
                  ? const CircularProgressIndicator()
                  : BigButton(
                      label: isLast ? 'צרו את הסיפור!' : 'המשך',
                      emoji: isLast ? '🪄' : null,
                      enabled: _selected != null,
                      onTap: _next,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
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
