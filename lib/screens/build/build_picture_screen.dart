import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/board.dart';
import '../../models/story.dart';
import '../../services/board_store.dart';
import '../../services/imagine_service.dart';
import '../../services/speech.dart';
import '../../services/story_store.dart';
import '../../theme.dart';
import '../../widgets/big_button.dart';
import '../../widgets/board_composer.dart';

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

  /// The user's OWN name for this thing — a lion may be their doll Arik.
  /// Long-press renames; speech and the generated picture follow it.
  String label;
  double dx; // 0..1 across the canvas
  double dy; // 0..1 down the canvas

  /// Visual size on the canvas (and "small/big" in the generated picture).
  double scale = 1;
}

/// A look for the generated picture. The prompt fragment leads the scene
/// description sent to the generator.
class _Style {
  const _Style(this.emoji, this.name, this.prompt);

  final String emoji;
  final String name;
  final String prompt;
}

const _kStyles = [
  _Style('🎨', 'ציור רך', 'איור דיגיטלי רך, צבעוני ושליו'),
  _Style('📷', 'כמו צילום', 'צילום מציאותי, יפה ומואר'),
  _Style('🖍️', 'ציור ילדים', 'ציור עליז בצבעי עפרון, פשוט ושמח'),
  _Style('💥', 'קומיקס', 'קומיקס צבעוני עם קווים ברורים'),
  _Style('🌊', 'צבעי מים', 'ציור עדין ורגוע בצבעי מים'),
  _Style('👾', 'משחק', 'פיקסל ארט צבעוני של משחק מחשב'),
];

class _BuildPictureScreenState extends State<BuildPictureScreen> {
  final Speech _speech = Speech();
  final Random _rand = Random();

  _Background? _bg;
  final List<_Placed> _placed = [];
  int _group = 0;

  bool _imagining = false;
  Uint8List? _realImage;

  /// The look of the generated picture — the creator's choice, like
  /// everything else here.
  _Style _style = _kStyles.first;

  /// What the current real picture was painted from — so the next 🎨 tap
  /// knows whether to EDIT it (new things, new style) or paint fresh.
  List<String> _paintedLabels = const [];
  _Style? _paintedStyle;

  /// Tap selects (highlight ring + visible action bar) — long-press proved
  /// unintuitive and motorically inaccessible; actions must be seen.
  _Placed? _selected;
  List<BoardWord> _boardWords = const [];
  final TextEditingController _compose = TextEditingController();

  /// The picture-chat input: once a real picture exists, you TALK to it —
  /// chips, board words, or typed text — and each message edits the image.
  final TextEditingController _editCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    BoardStore().load().then((words) {
      if (mounted && words.isNotEmpty) setState(() => _boardWords = words);
    });
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _speech.speak('איזו תמונה נבנה? בחרו רקע'));
  }

  @override
  void dispose() {
    _speech.dispose();
    _compose.dispose();
    _editCtl.dispose();
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

  /// The door out, here too — through the BOARD, not a keyboard. Every word
  /// tap lands on the picture IMMEDIATELY (no sentence bar, no send arrow):
  /// in a picture, the word is the action.
  void _addCustom() {
    _speech.speak('משהו אחר');
    _compose.clear();
    showBoardComposer(
      context,
      words: _boardWords,
      controller: _compose,
      addEachWord: true,
      onSubmit: (text) {
        final t = text.trim();
        if (t.isEmpty) return;
        _addElement(t, t);
      },
    );
  }

  void _undo() {
    if (_placed.isEmpty) return;
    _speech.speak('מחקנו את ${_placed.last.label}');
    setState(() => _placed.removeLast());
  }

  /// Long-press: "what do YOU call this?" — the user's own name wins, in
  /// speech and in the generated picture alike. Naming goes through the
  /// BOARD (their words and pictures), never only a keyboard — the board
  /// sheet is how someone without typing gives things their name.
  void _rename(_Placed p) {
    _speech.speak('איך קוראים לזה אצלך?');
    _compose.clear();
    showBoardComposer(
      context,
      words: _boardWords,
      controller: _compose,
      onSubmit: (text) {
        final t = text.trim();
        if (t.isEmpty) return;
        setState(() => p.label = t);
        _speech.speak(t);
      },
    );
  }

  /// Where and how big the user placed a thing, in words — dragging and
  /// resizing on the canvas MEAN something in the generated picture.
  String _placeDesc(_Placed p) {
    final h = p.dx < 0.33 ? 'בצד שמאל' : (p.dx > 0.67 ? 'בצד ימין' : 'במרכז');
    final v = p.dy < 0.35 ? 'למעלה' : (p.dy > 0.65 ? 'למטה' : '');
    final size = p.scale >= 1.6
        ? 'גדול מאוד'
        : (p.scale >= 1.2 ? 'גדול' : (p.scale <= 0.7 ? 'קטן' : ''));
    final bits =
        [if (size.isNotEmpty) size, h, if (v.isNotEmpty) v].join(' ');
    return '${p.label} ($bits)';
  }

  /// The scene, in the user's own words — this is the generator's prompt.
  String get _scenePrompt {
    final names = _placed.map(_placeDesc).join(', ');
    return '${_style.prompt}: '
        'סצנה ב${_bg!.name}${names.isEmpty ? '' : ', ובה $names'}. '
        'מקם כל דבר לפי התיאור שלו. בלי טקסט בתמונה.';
  }

  /// Things added since the picture was painted (multiset diff by label).
  List<_Placed> get _addedSincePainted {
    final prev = List<String>.from(_paintedLabels);
    final added = <_Placed>[];
    for (final p in _placed) {
      if (!prev.remove(p.label)) added.add(p);
    }
    return added;
  }

  Future<void> _makeReal() async {
    if (_bg == null || _imagining) return;
    _speech.speak('מציירים את התמונה שלך, רגע...');
    setState(() => _imagining = true);
    try {
      // A picture already exists → EDIT it, so the creation keeps growing
      // instead of starting over: add the new things, restyle if asked.
      final added = _addedSincePainted;
      final restyle = _paintedStyle != null && _paintedStyle != _style;
      final editing = _realImage != null && (added.isNotEmpty || restyle);
      final prompt = editing
          ? [
              if (added.isNotEmpty)
                'הוסף לתמונה: ${added.map(_placeDesc).join(', ')}.',
              if (restyle) 'צייר את כל התמונה מחדש בסגנון ${_style.prompt}.',
              if (!restyle) 'שמור על שאר התמונה בדיוק כפי שהיא.',
              'בלי טקסט בתמונה.',
            ].join(' ')
          : _scenePrompt;
      final bytes = await ImagineService()
          .imagine(prompt, baseImage: editing ? _realImage : null);
      if (!mounted) return;
      setState(() {
        _imagining = false;
        _realImage = bytes;
        _paintedLabels = _placed.map((p) => p.label).toList();
        _paintedStyle = _style;
      });
      _speech.speak('הנה התמונה שלך!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _imagining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('לא הצלחנו לצייר הפעם: $e')),
      );
    }
  }

  /// One message in the picture-chat: an instruction in the user's words
  /// edits the existing picture (the server keeps the rest as-is).
  Future<void> _editWords(String text) async {
    final t = text.trim();
    if (t.isEmpty || _realImage == null || _imagining) return;
    _editCtl.clear();
    _speech.speak(t);
    setState(() => _imagining = true);
    try {
      final bytes = await ImagineService().imagine(
        '$t. שמור על שאר התמונה כפי שהיא. בלי טקסט בתמונה.',
        baseImage: _realImage,
      );
      if (!mounted) return;
      setState(() {
        _imagining = false;
        _realImage = bytes;
      });
      _speech.speak('הנה!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _imagining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('לא הצלחנו לשנות הפעם: $e')),
      );
    }
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
        // Expanded + AspectRatio-inside-Center: the picture takes its share
        // of the screen and never pushes the palette and finish button off
        // (a wide window once swallowed the whole screen with canvas).
        Expanded(
          flex: 5,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Center(
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
                          left: p.dx * box.maxWidth - 28 * p.scale,
                          top: p.dy * box.maxHeight - 28 * p.scale,
                          child: GestureDetector(
                            onTap: () {
                              _speech.speak(p.label);
                              setState(
                                  () => _selected = _selected == p ? null : p);
                            },
                            onPanUpdate: (d) => setState(() {
                              p.dx = (p.dx + d.delta.dx / box.maxWidth)
                                  .clamp(0.05, 0.95);
                              p.dy = (p.dy + d.delta.dy / box.maxHeight)
                                  .clamp(0.05, 0.95);
                            }),
                            child: Container(
                              decoration: _selected == p
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(40),
                                      border: Border.all(
                                          color: Colors.white, width: 3),
                                      color: Colors.white24,
                                    )
                                  : null,
                              padding: const EdgeInsets.all(2),
                              // A custom word (no emoji for it) shows as a
                              // sticker chip, not raw giant text.
                              child: RegExp(r'[א-ת]').hasMatch(p.emoji)
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.92),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        p.label,
                                        style: TextStyle(
                                          fontSize: 20 * p.scale,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      p.emoji,
                                      style:
                                          TextStyle(fontSize: 56 * p.scale),
                                    ),
                            ),
                          ),
                        ),
                      // The REAL generated picture, painted over the sketch;
                      // the X returns to editing.
                      if (_realImage != null) ...[
                        Positioned.fill(
                          child: Image.memory(_realImage!, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: IconButton.filledTonal(
                            tooltip: 'חזרה לעריכה',
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: () =>
                                setState(() => _realImage = null),
                          ),
                        ),
                      ],
                      if (_imagining)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black38,
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: Colors.white),
                                SizedBox(height: 12),
                                Text(
                                  'מציירים את התמונה שלך... 🎨',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 18),
                                ),
                              ],
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
          ),
        ),
        // Visible actions for the selected element — no hidden gestures.
        if (_selected != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selected!.emoji} ${_selected!.label}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'להשמיע',
                  icon: const Icon(Icons.volume_up_rounded,
                      color: AppColors.primary),
                  onPressed: () => _speech.speak(_selected!.label),
                ),
                IconButton(
                  tooltip: 'קטן יותר',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: () {
                    _speech.speak('קטן יותר');
                    setState(() => _selected!.scale =
                        (_selected!.scale - 0.25).clamp(0.5, 2.5));
                  },
                ),
                IconButton(
                  tooltip: 'גדול יותר',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () {
                    _speech.speak('גדול יותר');
                    setState(() => _selected!.scale =
                        (_selected!.scale + 0.25).clamp(0.5, 2.5));
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  label: const Text('שם חדש', style: TextStyle(fontSize: 16)),
                  onPressed: () => _rename(_selected!),
                ),
                IconButton(
                  tooltip: 'להסיר מהתמונה',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    _speech.speak('מחקנו את ${_selected!.label}');
                    setState(() {
                      _placed.remove(_selected);
                      _selected = null;
                    });
                  },
                ),
              ],
            ),
          )
        else if (_realImage != null)
          _pictureChat()
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'מה נוסיף לתמונה? לחיצה על דבר בתמונה — בוחרת אותו',
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
          flex: 4,
          child: GridView.extent(
            padding: const EdgeInsets.all(12),
            maxCrossAxisExtent: 110,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _paletteTile('✨', 'משהו אחר', _addCustom),
              for (final (emoji, label) in _kElements[_group].items)
                _paletteTile(emoji, label, () => _addElement(emoji, label)),
            ],
          ),
        ),
        // The picture's look — the creator picks the style, chip-style.
        if (ImagineService.available)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in _kStyles)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      selected: _style == s,
                      label: Text('${s.emoji} ${s.name}',
                          style: const TextStyle(fontSize: 15)),
                      onSelected: (_) {
                        _speech.speak(s.name);
                        setState(() => _style = s);
                      },
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              if (ImagineService.available) ...[
                Expanded(
                  child: BigButton(
                    label: _realImage == null ? 'לצייר באמת' : 'לצייר שוב',
                    emoji: '🎨',
                    enabled: _placed.isNotEmpty && !_imagining,
                    onTap: _makeReal,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: BigButton(
                  label: 'סיימנו',
                  emoji: '🖼️',
                  enabled: _placed.isNotEmpty,
                  onTap: _finish,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Quick edit ideas — each tap talks to the picture right away.
  static const _kEditChips = [
    ('🌙', 'שיהיה לילה'),
    ('☀️', 'שיהיה יום'),
    ('❄️', 'שיהיה שלג'),
    ('🌈', 'עוד צבעים'),
    ('✨', 'עוד קסם'),
  ];

  /// The chat with the picture: quick chips, the board, or typed words —
  /// every message changes the existing picture ("like talking to you").
  Widget _pictureChat() {
    final pending = _addedSincePainted;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'בציור הבא יתווספו: ${pending.map((p) => p.label).join(', ')} — לחצו 🎨',
                style:
                    const TextStyle(fontSize: 14, color: AppColors.textSoft),
              ),
            ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (emoji, words) in _kEditChips)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ActionChip(
                      label: Text('$emoji $words',
                          style: const TextStyle(fontSize: 15)),
                      onPressed: () => _editWords(words),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              BoardComposerButton(
                words: _boardWords,
                controller: _editCtl,
                onSubmit: _editWords,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _editCtl,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _editWords,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'מה לשנות בתמונה?',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
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
              const SizedBox(width: 8),
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _editWords(_editCtl.text),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paletteTile(String emoji, String label, VoidCallback onTap) {
    return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
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
                );
  }
}
