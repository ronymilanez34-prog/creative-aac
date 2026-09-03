import 'package:flutter/material.dart';

import '../../data/choices.dart';
import '../../models/story.dart';
import '../../services/speech.dart';
import '../../services/story_generator.dart';
import '../../theme.dart';
import '../../widgets/big_button.dart';
import '../../widgets/choice_card.dart';
import '../story_view_screen.dart';

/// The guided story-building wizard: three calm, linear steps —
/// hero → place → event — plus an optional free-text idea. Choice over
/// typing, one question per screen, always a way back.
class BuildStoryScreen extends StatefulWidget {
  const BuildStoryScreen({super.key});

  @override
  State<BuildStoryScreen> createState() => _BuildStoryScreenState();
}

class _BuildStoryScreenState extends State<BuildStoryScreen> {
  final Speech _speech = Speech();
  final StorySpec _spec = StorySpec();
  final TextEditingController _idea = TextEditingController();
  final StoryGenerator _generator = const LocalTemplateStoryGenerator();

  int _step = 0;
  bool _building = false;

  static const _titles = [
    'מי הגיבור של הסיפור?',
    'איפה הסיפור קורה?',
    'מה קורה בסיפור?',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakTitle());
  }

  @override
  void dispose() {
    _speech.dispose();
    _idea.dispose();
    super.dispose();
  }

  void _speakTitle() => _speech.speak(_titles[_step]);

  List<Choice> get _options => switch (_step) {
        0 => kHeroes,
        1 => kPlaces,
        _ => kEvents,
      };

  Choice? get _selected => switch (_step) {
        0 => _spec.hero,
        1 => _spec.place,
        _ => _spec.event,
      };

  void _select(Choice c) {
    _speech.speak(c.label);
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

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
      _speakTitle();
    }
  }

  Future<void> _next() async {
    if (_step < 2) {
      setState(() => _step++);
      _speakTitle();
      return;
    }
    // Last step → build the story.
    if (!_spec.isComplete || _building) return;
    setState(() => _building = true);
    _spec.customIdea = _idea.text;
    final story = await _generator.generate(_spec);
    if (!mounted) return;
    setState(() => _building = false);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryViewScreen(story: story)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selected != null && !_building;
    final isLast = _step == 2;

    return Scaffold(
      appBar: AppBar(
        title: Text('שלב ${_step + 1} מתוך 3'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _back,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _StepDots(active: _step),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _titles[_step],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'הקרא',
                    icon: const Icon(Icons.volume_up_rounded,
                        color: AppColors.primary),
                    onPressed: _speakTitle,
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.all(16),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final c in _options)
                    ChoiceCard(
                      choice: c,
                      selected: _selected?.id == c.id,
                      onTap: () => _select(c),
                    ),
                ],
              ),
            ),
            if (isLast)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _idea,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'רוצה להוסיף משהו משלך? (לא חובה)',
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: BigButton(
                label: _building
                    ? 'רגע, בונים…'
                    : isLast
                        ? 'צור את הסיפור'
                        : 'המשך',
                emoji: _building ? null : (isLast ? '✨' : '⬅️'),
                enabled: canContinue,
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
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: on ? 16 : 11,
          height: on ? 16 : 11,
          decoration: BoxDecoration(
            color: on ? AppColors.primary : AppColors.border,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}
