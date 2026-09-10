import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/story.dart';
import '../../services/speech.dart';
import '../../services/story_store.dart';
import '../../theme.dart';
import '../../widgets/big_button.dart';

/// Building a PICTURE together — creation you can see. Choose a background,
/// then every tap adds an element onto the canvas itself; drag it wherever
/// you want. The picture grows under the user's fingers — visual authorship,
/// no text required. Fully local: works with no network.
class BuildPictureScreen extends StatefulWidget {
  const BuildPictureScreen({super.key});

  @override
  State<BuildPictureScreen> createState() => _BuildPictureScreenState();
}

class _Background {
  const _Background(this.emoji, this.name, this.top, this.bottom, this.ground);

  final String emoji;
  final String name;
  final Color top;
  final Color bottom;

  /// A base scenery emoji strip along the bottom (waves, trees...).
  final String ground;
}

const List<_Background> _kBackgrounds = [
  _Background('🌊', 'ים', Color(0xFF9AD0EC), Color(0xFF1E6FA8), '🌊🌊🌊🌊🌊🌊'),
  _Background('🌳', 'יער', Color(0xFFBFE3B4), Color(0xFF3E7C4F), '🌲🌳🌲🌳🌲🌳'),
  _Background('🌌', 'חלל', Color(0xFF2C2A4A), Color(0xFF0B0A1F), '✨⭐✨⭐✨⭐'),
  _Background('🏙️', 'עיר', Color(0xFFD7E1EA), Color(0xFF7E93A6), '🏢🏠🏢🏬🏢🏠'),
  _Background('🏜️', 'מדבר', Color(0xFFF6D8A8), Color(0xFFC98F4E), '🌵🏜️🌵🏜️🌵🏜️'),
  _Background('⛄', 'שלג', Color(0xFFE8F1F8), Color(0xFF9FC4DD), '⛄🌨️⛄🌨️⛄🌨️'),
];

class _ElementGroup {
  const _ElementGroup(this.emoji, this.name, this.items);

  final String emoji;
  final String name;
  final List<(String, String)> items; // (emoji, label)
}

const List<_ElementGroup> _kElements = [
  _ElementGroup('🐾', 'חיות', [
    ('🐶', 'כלב'),
    ('🐱', 'חתול'),
    ('🦁', 'אריה'),
    ('🐘', 'פיל'),
    ('🦋', 'פרפר'),
    ('🐟', 'דג'),
    ('🐢', 'צב'),
    ('🦅', 'נשר'),
  ]),
  _ElementGroup('🧑', 'אנשים', [
    ('👧', 'ילדה'),
    ('👦', 'ילד'),
    ('🧑', 'איש'),
    ('👩', 'אישה'),
    ('🧑‍🚀', 'אסטרונאוט'),
    ('🦸', 'גיבור'),
  ]),
  _ElementGroup('☀️', 'שמיים', [
    ('☀️', 'שמש'),
    ('🌙', 'ירח'),
    ('⭐', 'כוכב'),
    ('☁️', 'ענן'),
    ('🌈', 'קשת'),
    ('🎈', 'בלון'),
    ('✈️', 'מטוס'),
    ('🚀', 'חללית'),
  ]),
  _ElementGroup('🎁', 'דברים', [
    ('⛵', 'סירה'),
    ('🚗', 'מכונית'),
    ('🏰', 'טירה'),
    ('⚽', 'כדור'),
    ('🌸', 'פרח'),
    ('🍦', 'גלידה'),
    ('🎸', 'גיטרה'),
    ('🪁', 'עפיפון'),
  ]),
];

class _Placed {
  _Placed(this.emoji, this.label, this.dx, this.dy);

  final String emoji;
  final String label;
  double dx; // 0..1 across the canvas
  double dy; // 0..1 down the canvas
}

class _BuildPictureScreenState extends State<BuildPictureScreen> {
  final Speech _speech = Speech();
  final Random _rand = Random();

  _Background? _bg;
  final List<_Placed> _placed = [];
  int _group = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _speech.speak('איזו תמונה נבנה? בחרו רקע'));
  }

  @override
  void dispose() {
    _speech.dispose();
    super.dispose();
  }

  void _pickBackground(_Background b) {
    _speech.speak(b.name);
    setState(() => _bg = b);
  }

  void _addElement(String emoji, String label) {
    _speech.speak(label);
    setState(() {
      _placed.add(_Placed(
        emoji,
        label,
        0.12 + _rand.nextDouble() * 0.7,
        0.12 + _rand.nextDouble() * 0.55,
      ));
    });
  }

  void _undo() {
    if (_placed.isEmpty) return;
    _speech.speak('מחקנו את ${_placed.last.label}');
    setState(() => _placed.removeLast());
  }

  Future<void> _finish() async {
    if (_bg == null) return;
    final names = _placed.map((p) => p.label).toList();
    final line = names.isEmpty
        ? 'תמונה ב${_bg!.name}.'
        : 'תמונה ב${_bg!.name}, עם ${names.join(', ')}.';
    final collage =
        '${_bg!.emoji}  ${_placed.map((p) => p.emoji).join(' ')}';
    final now = DateTime.now();
    final story = Story(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'תמונה ב${_bg!.name}',
      pages: [StoryPage(emoji: '🖼️', text: '$collage\n$line')],
      createdAtMs: now.millisecondsSinceEpoch,
    );
    await StoryStore().save(story);
    if (!mounted) return;
    _speech.speak('התמונה נשמרה. $line');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('התמונה נשמרה ב"הסיפורים שלי" 🖼️')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_bg == null ? 'בואו נבנה תמונה' : 'התמונה שלך'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_bg != null)
            IconButton(
              tooltip: 'מחיקת הדבר האחרון',
              icon: const Icon(Icons.undo_rounded),
              onPressed: _placed.isEmpty ? null : _undo,
            ),
        ],
      ),
      body: SafeArea(
        child: _bg == null ? _backgroundPicker() : _builder(),
      ),
    );
  }

  Widget _backgroundPicker() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            'איפה התמונה שלנו?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ),
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              for (final b in _kBackgrounds)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _pickBackground(b),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [b.top, b.bottom],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(b.emoji, style: const TextStyle(fontSize: 44)),
                        Text(
                          b.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [Shadow(blurRadius: 6)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _builder() {
    final bg = _bg!;
    return Column(
      children: [
        // The canvas — the creation itself, growing with every tap.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: LayoutBuilder(
              builder: (context, box) => ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [bg.top, bg.bottom],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        bottom: 4,
                        left: 0,
                        right: 0,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Text(
                            bg.ground,
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                      ),
                      for (final p in _placed)
                        Positioned(
                          left: p.dx * box.maxWidth - 28,
                          top: p.dy * box.maxHeight - 28,
                          child: GestureDetector(
                            onTap: () => _speech.speak(p.label),
                            onPanUpdate: (d) => setState(() {
                              p.dx = (p.dx + d.delta.dx / box.maxWidth)
                                  .clamp(0.05, 0.95);
                              p.dy = (p.dy + d.delta.dy / box.maxHeight)
                                  .clamp(0.05, 0.95);
                            }),
                            child: Text(
                              p.emoji,
                              style: const TextStyle(fontSize: 56),
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
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'מה נוסיף לתמונה? (אפשר לגרור כל דבר למקום שלו)',
            style: TextStyle(fontSize: 16, color: AppColors.textSoft),
          ),
        ),
        // Category tabs.
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var i = 0; i < _kElements.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    selected: _group == i,
                    label: Text(
                      '${_kElements[i].emoji} ${_kElements[i].name}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    onSelected: (_) {
                      _speech.speak(_kElements[i].name);
                      setState(() => _group = i);
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.all(12),
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final (emoji, label) in _kElements[_group].items)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _addElement(emoji, label),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 32)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: BigButton(
            label: 'סיימנו — לשמור את התמונה',
            emoji: '🖼️',
            enabled: _placed.isNotEmpty,
            onTap: _finish,
          ),
        ),
      ],
    );
  }
}
