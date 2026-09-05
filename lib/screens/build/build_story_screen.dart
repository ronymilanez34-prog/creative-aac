import 'package:flutter/material.dart';

import '../../data/choices.dart';
import '../../models/story.dart';
import '../../services/speech.dart';
import '../../theme.dart';
import '../../widgets/big_button.dart';
import '../../widgets/choice_card.dart';
import '../story_view_screen.dart';

/// The guided story-building wizard. Two calm setup steps (hero, place) and
/// then the heart of it: the story grows PAGE BY PAGE, one user choice at a
/// time, until the user decides it is done. The machine never invents the
/// story — it only phrases the user's own choices (authorship rule).
class BuildStoryScreen extends StatefulWidget {
  const BuildStoryScreen({super.key});

  @override
  State<BuildStoryScreen> createState() => _BuildStoryScreenState();
}

class _BuildStoryScreenState extends State<BuildStoryScreen> {
  final Speech _speech = Speech();
  final TextEditingController _idea = TextEditingController();
  final ScrollController _pagesScroll = ScrollController();

  Choice? _hero;
  Choice? _place;
  final List<StoryPage> _pages = [];

  /// 0 = pick hero, 1 = pick place, 2 = build the story page by page.
  int _step = 0;

  static const _titles = [
    'מי הגיבור של הסיפור?',
    'איפה הסיפור קורה?',
    'מה קורה עכשיו?',
  ];

  // Round-robin connectors so consecutive pages read naturally.
  static const _connectors = ['ואז', 'פתאום', 'אחר כך', 'לאט לאט', 'ובסוף היום'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakTitle());
  }

  @override
  void dispose() {
    _speech.dispose();
    _idea.dispose();
    _pagesScroll.dispose();
    super.dispose();
  }

  void _speakTitle() => _speech.speak(_titles[_step]);

  List<Choice> get _options => switch (_step) {
        0 => kHeroes,
        1 => kPlaces,
        _ => kEvents,
      };

  void _select(Choice c) {
    _speech.speak(c.label);
    switch (_step) {
      case 0:
        setState(() {
          _hero = c;
          _step = 1;
        });
        _speakTitle();
      case 1:
        setState(() {
          _place = c;
          _step = 2;
          // The opening pages phrase the user's own two choices.
          _pages.add(StoryPage(
            emoji: _hero!.emoji,
            text: 'היֹה היה ${_hero!.label}. '
                'כל בוקר ${_hero!.label} התעורר עם חיוך גדול.',
          ));
          _pages.add(StoryPage(
            emoji: c.emoji,
            text: 'יום אחד ${_hero!.label} הגיע ${c.label}. '
                'הכול שם היה חדש ומעניין.',
          ));
        });
        _speech.speak(_pages.map((p) => p.text).join(' '));
        _scrollToEnd();
      default:
        // Every tap adds exactly one page — the user drives the plot.
        final connector = _connectors[
            (_pages.length - 2).clamp(0, 1000) % _connectors.length];
        final page = StoryPage(
          emoji: c.emoji,
          text: '$connector ${_hero!.label} ${c.label}!',
        );
        setState(() => _pages.add(page));
        _speech.speak(page.text);
        _scrollToEnd();
    }
  }

  void _addIdea() {
    final text = _idea.text.trim();
    if (text.isEmpty) return;
    final page = StoryPage(emoji: '💡', text: text);
    setState(() => _pages.add(page));
    _idea.clear();
    _speech.speak(page.text);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pagesScroll.hasClients) return;
      _pagesScroll.animateTo(
        _pagesScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (_step == 2 && _pages.length > 2) {
        // Inside the loop: back removes the last page (undo, not exit).
        _pages.removeLast();
      } else if (_step == 2) {
        _pages.clear();
        _place = null;
        _step = 1;
      } else {
        _hero = null;
        _step = 0;
      }
    });
    _speakTitle();
  }

  Future<void> _finish() async {
    if (_pages.isEmpty) return;
    final ending = StoryPage(
      emoji: '🌟',
      text: 'וזה היה הסיפור של ${_hero!.label}. הסוף.',
    );
    final now = DateTime.now();
    final story = Story(
      id: now.microsecondsSinceEpoch.toString(),
      title: '${_hero!.label} ${_place!.label}',
      pages: [..._pages, ending],
      createdAtMs: now.millisecondsSinceEpoch,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryViewScreen(story: story)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final building = _step == 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          building ? 'הסיפור שלך — ${_pages.length} עמודים' : 'שלב ${_step + 1}',
        ),
        leading: IconButton(
          tooltip: building ? 'מחיקת העמוד האחרון' : 'חזרה',
          icon: Icon(building ? Icons.undo_rounded : Icons.arrow_forward),
          onPressed: _back,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!building) ...[
              const SizedBox(height: 12),
              _StepDots(active: _step),
            ],
            if (building)
              Expanded(
                flex: 2,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.separated(
                    controller: _pagesScroll,
                    itemCount: _pages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => Text(
                      '${_pages[i].emoji}  ${_pages[i].text}',
                      style: const TextStyle(
                          fontSize: 18, height: 1.4, color: AppColors.text),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _titles[_step],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
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
              flex: 3,
              child: GridView.count(
                padding: const EdgeInsets.all(16),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final c in _options)
                    ChoiceCard(
                      choice: c,
                      selected: !building &&
                          (_step == 0
                              ? _hero?.id == c.id
                              : _place?.id == c.id),
                      onTap: () => _select(c),
                    ),
                ],
              ),
            ),
            if (building) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _idea,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addIdea(),
                        style: const TextStyle(fontSize: 18),
                        decoration: InputDecoration(
                          hintText: 'או ספר/י במילים שלך מה קורה…',
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppColors.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _addIdea,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.add_rounded, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: BigButton(
                  label: 'סיימנו — לסגור את הסיפור',
                  emoji: '✨',
                  enabled: _pages.length > 2,
                  onTap: _finish,
                ),
              ),
            ],
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
      children: List.generate(2, (i) {
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
