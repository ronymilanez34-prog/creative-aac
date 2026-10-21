import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/companion.dart';
import '../models/profile.dart';
import '../models/story.dart';
import '../services/board_mode_prefs.dart';
import '../services/board_store.dart';
import '../services/companion_service.dart';
import '../services/creation_image.dart';
import '../services/hebrew_text.dart';
import '../services/imagine_service.dart';
import '../services/interaction_log.dart';
import '../services/profile_store.dart';
import '../services/scene_prompt.dart';
import '../services/speech.dart';
import '../services/story_store.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/board_grid.dart';
import '../widgets/board_image.dart';
import '../widgets/full_image_view.dart';
import '../widgets/quick_bar.dart';
import '../widgets/quick_fire_overlay.dart';
import 'my_words_screen.dart';

export '../widgets/board_grid.dart' show boardColor;

/// "יוצרים מהלוח שלי" — creation that rides on the user's own board (21.10).
///
/// The principle: do not re-teach. The user learned, over years, where each
/// word sits and how pages open; this screen keeps all of it one to one and
/// only changes what the words DO: here they create, they do not request.
///
/// Three areas, top to bottom (iPad in portrait):
///  • the creation: the picture and the chosen words as their own board
///    symbols, the companion's telling small under them — on a warm
///    background unlike the board, so it is clear this is the place of
///    making (a request for "מים" here brings no water);
///  • the companion: what it says, as a row of symbols taken from the
///    user's board (a word the board lacks is a bare text card, marked
///    differently), spoken aloud, each symbol lit in turn;
///  • the board: the current page in its own grid, same rows, columns and
///    positions; a link button opens its page, a fixed button goes home.
///
/// Built apart from [CompanionScreen] so the pilot can compare the two;
/// the companion service, scene painting, saving to "my stories" and the
/// emergency strip are the same code.
class BoardCreateScreen extends StatefulWidget {
  const BoardCreateScreen({
    super.key,
    required this.service,
    this.layout,
    this.mode,
  });

  final CompanionService service;

  /// The board to show; null loads the imported one (test seam).
  final BoardLayout? layout;

  /// The expression pattern; null loads the partner's setting (test seam).
  final BoardExpressionMode? mode;

  @override
  State<BoardCreateScreen> createState() => _BoardCreateScreenState();
}

/// One word of the companion's answer as the user sees it: with its button
/// from their board when the board has that word, bare otherwise.
class BoardSaySymbol {
  const BoardSaySymbol({required this.word, this.button});

  final String word;
  final BoardButton? button;

  bool get fromBoard => button != null;
}

class _BoardCreateScreenState extends State<BoardCreateScreen> {
  final Speech _speech = Speech();
  final InteractionLog _log = InteractionLog();

  BoardLayout? _layout;
  bool _loading = true;
  String? _pageId;
  BoardExpressionMode _mode = BoardExpressionMode.immediate;
  String _companionName = kDefaultCompanionName;

  /// Words gathered in the tray (tray mode only).
  final List<BoardButton> _tray = [];

  /// The creation: every word the creator sent, as their own buttons.
  final List<BoardButton> _chosen = [];

  /// The companion's telling of the page (page_story).
  String _pageStory = '';

  /// The visible conversation as the backend needs it (its only memory).
  final List<TurnMessage> _history = [];

  CompanionTurn? _turn;
  bool _busy = false;
  bool _failed = false;
  String _lastError = '';
  String _lastInput = '';

  /// The companion's last words as symbols, and which one is lit now.
  List<BoardSaySymbol> _say = const [];
  int _lit = -1;
  final List<Timer> _litTimers = [];

  String? _lastScene;
  Uint8List? _sceneImage;
  bool _painting = false;
  String? _pendingScene;
  String _paintError = '';

  late final String _storyId;
  int _savedWords = 0;
  bool _sceneDirty = false;
  bool get _hasUnsaved =>
      (_chosen.isNotEmpty && _savedWords != _chosen.length) || _sceneDirty;

  QuickFire? _activeQuickFire;

  String get _modeName =>
      _mode == BoardExpressionMode.tray ? 'tray' : 'immediate';

  BoardPage? get _page {
    final l = _layout;
    if (l == null) return null;
    final id = _pageId;
    return (id == null ? null : l.page(id)) ?? l.home;
  }

  @override
  void initState() {
    super.initState();
    _storyId = DateTime.now().microsecondsSinceEpoch.toString();
    _turn = widget.service.opening();
    final given = widget.layout;
    if (given != null) {
      _layout = given;
      _pageId = given.rootId;
      _loading = false;
    } else {
      _loadLayout();
    }
    final mode = widget.mode;
    if (mode != null) {
      _mode = mode;
    } else {
      BoardModePrefs().load().then((m) {
        if (mounted) setState(() => _mode = m);
      });
    }
    ProfileStore().load().then((p) {
      if (mounted) setState(() => _companionName = p.effectiveCompanionName);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final t = _turn;
      if (t != null && _layout != null) _showSay(t.say, speakText: t.say);
    });
  }

  Future<void> _loadLayout() async {
    final layout = await BoardStore().loadLayout();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _pageId = layout?.rootId;
      _loading = false;
    });
    final t = _turn;
    if (layout != null && t != null) _showSay(t.say, speakText: t.say);
  }

  @override
  void dispose() {
    for (final t in _litTimers) {
      t.cancel();
    }
    _speech.dispose();
    widget.service.dispose();
    super.dispose();
  }

  void _speak(String text) => _speech.speak(text);

  // ---------------------------------------------------------------- board

  void _onButton(BoardButton b) {
    final page = _page;
    if (page == null) return;
    if (b.isLink) {
      unawaited(_log.logBoardChoice(
        label: b.label,
        pageId: page.id,
        row: b.row,
        col: b.col,
        mode: _modeName,
        kind: 'board_nav',
      ));
      _openPage(b.loadBoardId!, say: b.label);
      return;
    }
    unawaited(_log.logBoardChoice(
      label: b.label,
      pageId: page.id,
      row: b.row,
      col: b.col,
      mode: _modeName,
      kind: 'board_word',
    ));
    if (_mode == BoardExpressionMode.tray) {
      // Heard at once, as on their board; sent on "שלח".
      _speak(b.spokenText);
      setState(() => _tray.add(b));
      return;
    }
    unawaited(_send([b]));
  }

  void _openPage(String id, {String say = ''}) {
    final l = _layout;
    if (l == null || l.page(id) == null) return;
    if (say.isNotEmpty) _speak(say);
    setState(() => _pageId = id);
  }

  void _goHome() {
    final l = _layout;
    if (l == null) return;
    _openPage(l.rootId);
  }

  void _sendTray() {
    if (_tray.isEmpty) return;
    unawaited(_send(List.of(_tray)));
  }

  void _clearTray() {
    if (_tray.isEmpty) return;
    setState(() => _tray.clear());
  }

  // ------------------------------------------------------------ companion

  String get _creationText => _chosen.map((b) => b.label).join(' · ');

  /// The creation as the model should see it: the creator's words and the
  /// companion's telling so far — it continues, never restarts.
  String get _creationForModel {
    if (_chosen.isEmpty && _pageStory.isEmpty) return '';
    return 'המילים שלו: $_creationText'
        '${_pageStory.isEmpty ? '' : '\nסיפרת: $_pageStory'}';
  }

  Future<void> _send(List<BoardButton> words) async {
    if (words.isEmpty) return;
    if (_busy) {
      // A press mid-turn is heard, not swallowed (20.10).
      _speak('רגע… ${words.map((b) => b.label).join(' ')}');
      return;
    }
    final text =
        words.map((b) => b.spokenText.trim()).where((t) => t.isNotEmpty).join(' ');
    if (text.isEmpty) {
      // A picture-only button (a person's photo, an arrow) has no word
      // yet: it stands on the stage as chosen, but there is nothing to
      // say to the companion, so no turn starts — and nothing gets stuck
      // (iPad 21.10: the screen froze on exactly this press).
      // TODO(words): let a partner name picture-only buttons, so they can
      // reach the companion too.
      setState(() {
        _chosen.addAll(words);
        _tray.clear();
      });
      return;
    }
    setState(() {
      _chosen.addAll(words);
      _tray.clear();
      _busy = true;
      _failed = false;
      _lastInput = text;
    });
    _speak(text);
    unawaited(_log.logBoardSend(wordCount: words.length, mode: _modeName));
    await _performTurn(text);
  }

  Future<void> _retry() => _performTurn(_lastInput);

  Future<void> _performTurn(String input) async {
    if (input.trim().isEmpty) {
      // Never leave the screen busy with nothing in flight.
      if (_busy) setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final next = await widget.service.turn(
        input,
        creationSoFar: _creationForModel,
        sceneSoFar: _lastScene,
        history: List.unmodifiable(_history),
        boardMode: true,
      );
      if (!mounted) return;
      _history.add((role: 'user', text: input));
      _history.add((role: 'assistant', text: next.say));
      while (_history.length > 12) {
        _history.removeAt(0);
      }
      _applyTurn(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _lastError = '$e';
      });
      _speak('רגע, משהו השתבש. אפשר לנסות שוב.');
    }
  }

  void _applyTurn(CompanionTurn turn) {
    if (turn.safeguard) unawaited(_log.logSafeguard());
    final story = turn.pageStory?.trim() ?? '';
    setState(() {
      _turn = turn;
      _busy = false;
      _failed = false;
      if (story.isNotEmpty) _pageStory = story;
    });
    // A confirm question is spoken whole — question and choices — the
    // screen never assumes reading; the symbols show the message itself.
    final c = turn.confirm;
    final spoken = turn.needsConfirmation && c != null && c.options.isNotEmpty
        ? '${turn.say} ${c.question} ${c.options.join(', או ')}'
        : turn.say;
    _showSay(turn.say, speakText: spoken);

    final scene = turn.sceneUpdate?.trim() ?? '';
    if (scene.isNotEmpty) {
      _lastScene = scene;
      if (ImagineService.available) unawaited(_paintScene(scene));
    }
  }

  /// Shows the companion's words as board symbols, speaks them, and lights
  /// each symbol in turn.
  void _showSay(String say, {required String speakText}) {
    final symbols = symbolsFor(say, _layout);
    unawaited(_log.logBoardSay(
      fromBoard: [for (final s in symbols) if (s.fromBoard) s.word],
      notFromBoard: [for (final s in symbols) if (!s.fromBoard) s.word],
    ));
    setState(() => _say = symbols);
    _speakAndLight(speakText, symbols);
  }

  void _replay() {
    final t = _turn;
    if (t == null) return;
    _speakAndLight(t.say, _say);
  }

  void _speakAndLight(String text, List<BoardSaySymbol> symbols) {
    _speak(text);
    for (final t in _litTimers) {
      t.cancel();
    }
    _litTimers.clear();
    // TODO(sync): light by the voice, not a clock. flutter_tts reports
    // word progress only on some platforms (setProgressHandler); until it
    // is wired, each symbol gets a slot sized by its word's length at the
    // speech rate in use (0.45) — close enough to follow, not exact.
    var at = 0;
    for (var i = 0; i < symbols.length; i++) {
      final ms = 280 + 70 * symbols[i].word.length;
      final index = i;
      _litTimers.add(Timer(Duration(milliseconds: at), () {
        if (mounted) setState(() => _lit = index);
      }));
      at += ms;
    }
    _litTimers.add(Timer(Duration(milliseconds: at + 200), () {
      if (mounted) setState(() => _lit = -1);
    }));
  }

  // -------------------------------------------------------------- picture

  Future<void> _paintScene(String scene) async {
    if (_painting) {
      // Latest wins: every scene_update describes the whole scene.
      _pendingScene = scene;
      return;
    }
    _painting = true;
    try {
      final base = _sceneImage;
      final bytes = await ImagineService().imagine(
        scenePaintPrompt(scene, hasBase: base != null, freshPage: false),
        baseImage: base == null ? null : await shrinkForStorage(base),
      );
      if (!mounted) return;
      setState(() {
        _sceneImage = bytes;
        _sceneDirty = true;
        _paintError = '';
      });
    } catch (e) {
      if (mounted) setState(() => _paintError = 'הציור לא הצליח: $e');
    }
    _painting = false;
    final next = _pendingScene;
    if (mounted && next != null) {
      _pendingScene = null;
      await _paintScene(next);
    }
  }

  // ----------------------------------------------------------------- save

  Future<void> _save() async {
    if (_chosen.isEmpty && _sceneImage == null) return;
    final title = _chosen.isEmpty
        ? 'מהלוח שלי'
        : _chosen.take(4).map((b) => b.label).join(' ');
    final image = _sceneImage;
    final story = Story(
      id: _storyId,
      title: title,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      pages: [
        StoryPage(
          text: _creationText,
          told: _pageStory,
          emoji: '🧩',
          imageB64:
              image == null ? null : base64Encode(await shrinkForStorage(image)),
        ),
      ],
    );
    await StoryStore().save(story);
    if (!mounted) return;
    setState(() {
      _savedWords = _chosen.length;
      _sceneDirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('נשמר ב"הסיפורים שלי" 📚')),
    );
  }

  Future<void> _confirmExit() async {
    if (!_hasUnsaved) {
      Navigator.of(context).pop();
      return;
    }
    _speak('לשמור את היצירה לפני שיוצאים?');
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('לשמור את היצירה?', textAlign: TextAlign.center),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BigButton(
                  label: 'לשמור ולצאת',
                  emoji: '💾',
                  onTap: () => Navigator.of(ctx).pop('save'),
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'להמשיך ליצור',
                  emoji: '🎨',
                  color: AppColors.accent,
                  onTap: () => Navigator.of(ctx).pop('stay'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('discard'),
                  child: const Text('לצאת בלי לשמור'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      await _save();
      if (mounted) Navigator.of(context).pop();
    } else if (choice == 'discard') {
      Navigator.of(context).pop();
    }
  }

  // ----------------------------------------------------------- quick fire

  void _onQuickFire(QuickFire q) {
    if (q.label == 'סיימתי') {
      unawaited(_finish(q));
      return;
    }
    _speech.stop();
    if (q.label != 'חזק מדי') _speech.speak(q.spoken);
    unawaited(_log.logQuickFire(q.label));
    setState(() => _activeQuickFire = q);
  }

  Future<void> _finish(QuickFire q) async {
    _speech.stop();
    unawaited(_log.logQuickFire(q.label));
    if (_chosen.isNotEmpty || _sceneImage != null) {
      await _save();
      if (!mounted) return;
      _speech.speak('סיימתי. היצירה נשמרה.');
    } else {
      _speech.speak(q.spoken);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final page = _page;
    if (!_loading && (layout == null || page == null)) {
      return _NoBoard(onImported: () {
        setState(() => _loading = true);
        _loadLayout();
      });
    }
    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => unawaited(_speech.warmUp()),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('יוצרים מהלוח שלי'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward),
              onPressed: _confirmExit,
            ),
            actions: [
              IconButton(
                tooltip: 'שמירת היצירה',
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed:
                    _chosen.isEmpty && _sceneImage == null ? null : _save,
              ),
            ],
          ),
          body: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, box) {
                    final h = box.maxHeight;
                    return Stack(
                      children: [
                        Column(
                          children: [
                            _Stage(
                              chosen: _chosen,
                              image: _sceneImage,
                              story: _pageStory,
                              storyLabel: '$_companionName מספר',
                              paintError: _paintError,
                              height: h * 0.28,
                              onSpeak: _speak,
                            ),
                            _PazStrip(
                              symbols: _say,
                              lit: _lit,
                              busy: _busy,
                              failed: _failed,
                              errorDetail: _lastError,
                              maxHeight: h * 0.17,
                              onReplay: _replay,
                              onRetry: _retry,
                            ),
                            Expanded(
                              child: BoardPanel(
                                page: page!,
                                isHome: page.id == layout!.rootId,
                                tray: _mode == BoardExpressionMode.tray ? _tray : null,
                                modeLabel: _mode == BoardExpressionMode.tray ? 'חלונית' : 'מיידי',
                                onButton: _onButton,
                                onHome: _goHome,
                                onSend: _sendTray,
                                onClear: _clearTray,
                              ),
                            ),
                            QuickBar(onFire: _onQuickFire),
                          ],
                        ),
                        if (_activeQuickFire != null)
                          Positioned.fill(
                            child: QuickFireOverlay(
                              fire: _activeQuickFire!,
                              onDismiss: () {
                                _speech.stop();
                                setState(() => _activeQuickFire = null);
                              },
                            ),
                          ),
                      ],
                    );
                  }),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ words

/// Splits the companion's words and finds each one's button on the user's
/// board. Up to three words at a time are tried as one label (boards carry
/// "אני רוצה" as one button); a single-letter Hebrew prefix (ו, ה, ב, ל, מ,
/// ש, כ) is peeled once when the bare word has no button but the stem does.
/// Pure, so it is testable without a screen.
List<BoardSaySymbol> symbolsFor(String say, BoardLayout? layout) {
  final words = stripNikud(say)
      .split(RegExp(r'\s+'))
      .map((w) => w.replaceAll(RegExp(r"[^\p{L}\p{N}'’׳]", unicode: true), ''))
      .where((w) => w.isNotEmpty)
      .toList();
  if (layout == null) return [for (final w in words) BoardSaySymbol(word: w)];
  final index = layout.byLabel;
  final out = <BoardSaySymbol>[];
  var i = 0;
  while (i < words.length) {
    var matched = false;
    for (var n = 3; n >= 1; n--) {
      if (i + n > words.length) continue;
      final phrase = words.sublist(i, i + n).join(' ');
      final hit = index[phrase.toLowerCase()];
      if (hit != null) {
        out.add(BoardSaySymbol(word: phrase, button: hit));
        i += n;
        matched = true;
        break;
      }
    }
    if (matched) continue;
    final w = words[i];
    BoardButton? hit;
    if (w.length > 2 && 'והבלמשכ'.contains(w[0])) {
      hit = index[w.substring(1).toLowerCase()];
    }
    out.add(BoardSaySymbol(word: w, button: hit));
    i++;
  }
  return out;
}

// ---------------------------------------------------------------- widgets

/// The place of making: warm, unlike the board below, so a word pressed
/// here is a brick of the creation and never a request.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.chosen,
    required this.image,
    required this.story,
    required this.storyLabel,
    required this.paintError,
    required this.height,
    required this.onSpeak,
  });

  final List<BoardButton> chosen;
  final Uint8List? image;
  final String story;
  final String storyLabel;
  final String paintError;
  final double height;
  final ValueChanged<String> onSpeak;

  @override
  Widget build(BuildContext context) {
    final img = image;
    final text = chosen.map((b) => b.label).join(' ');
    return Container(
      height: height,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8B98A), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '✨ מקום היצירה',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB2641C),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: chosen.isEmpty && img == null
                ? const Center(
                    child: Text(
                      'כאן תיבנה היצירה שלך. בחרו מילה מהלוח למטה.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: AppColors.textSoft),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (img != null)
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () => showFullImage(context, img),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 700),
                                child: Image.memory(
                                  img,
                                  key: ValueKey(identityHashCode(img)),
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (img != null) const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GestureDetector(
                                onTap: text.isEmpty ? null : () => onSpeak(text),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final b in chosen)
                                      BoardSymbolCard(
                                        label: b.label,
                                        imagePath: b.imagePath,
                                        size: 40,
                                      ),
                                  ],
                                ),
                              ),
                              if (story.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => onSpeak(story),
                                  child: Text(
                                    '$storyLabel: ${stripNikud(story)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: AppColors.textSoft,
                                    ),
                                  ),
                                ),
                              ],
                              if (paintError.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    paintError,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.redAccent),
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
      ),
    );
  }
}

/// The companion's message as a row of the user's own symbols.
class _PazStrip extends StatelessWidget {
  const _PazStrip({
    required this.symbols,
    required this.lit,
    required this.busy,
    required this.failed,
    required this.errorDetail,
    required this.maxHeight,
    required this.onReplay,
    required this.onRetry,
  });

  final List<BoardSaySymbol> symbols;
  final int lit;
  final bool busy;
  final bool failed;
  final String errorDetail;
  final double maxHeight;
  final VoidCallback onReplay;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight, minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('🖌️', style: TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: failed
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('משהו השתבש בדרך. ננסה שוב?',
                                style: TextStyle(
                                    fontSize: 16, color: AppColors.textSoft)),
                            if (errorDetail.isNotEmpty)
                              Text(errorDetail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.textSoft)),
                            TextButton.icon(
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('נסה שוב'),
                            ),
                          ],
                        )
                      : busy && symbols.isEmpty
                          ? const Text('…',
                              style: TextStyle(
                                  fontSize: 22, color: AppColors.textSoft))
                          : Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (var i = 0; i < symbols.length; i++)
                                  _SaySymbolCard(
                                      symbol: symbols[i], lit: i == lit),
                              ],
                            ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'הקרא שוב',
              icon: const Icon(Icons.volume_up_rounded, color: AppColors.primary),
              onPressed: symbols.isEmpty ? null : onReplay,
            ),
          ],
        ),
      ),
    );
  }
}

/// One word of the companion: its board button when the board has it (the
/// picture the user knows), a bare, differently styled text card when it
/// does not — the visible edge of their language.
class _SaySymbolCard extends StatelessWidget {
  const _SaySymbolCard({required this.symbol, required this.lit});

  final BoardSaySymbol symbol;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final from = symbol.fromBoard;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: lit
            ? AppColors.accent.withValues(alpha: 0.35)
            : from
                ? AppColors.surface
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: lit
              ? AppColors.accent
              : from
                  ? AppColors.border
                  : AppColors.textSoft.withValues(alpha: 0.6),
          width: lit ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (from)
            BoardImage(imagePath: symbol.button!.imagePath, emoji: '', size: 36)
          else
            const Icon(Icons.short_text, size: 20, color: AppColors.textSoft),
          Text(
            symbol.word,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontStyle: from ? FontStyle.normal : FontStyle.italic,
              color: from ? AppColors.text : AppColors.textSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// No board imported yet: say so, and point to the import.
class _NoBoard extends StatelessWidget {
  const _NoBoard({required this.onImported});

  final VoidCallback onImported;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('יוצרים מהלוח שלי'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧩', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              const Text(
                'עוד לא יובא לוח. מייבאים את הלוח שלו ב"המילים שלי", וחוזרים לכאן.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: AppColors.textSoft),
              ),
              const SizedBox(height: 20),
              BigButton(
                label: 'המילים שלי',
                emoji: '💬',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyWordsScreen()),
                  );
                  onImported();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
