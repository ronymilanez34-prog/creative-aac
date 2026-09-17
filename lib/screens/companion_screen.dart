import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/companion.dart';
import '../models/story.dart';
import '../services/board_store.dart';
import '../services/chip_layout.dart';
import '../services/companion_service.dart';
import '../services/creation_context.dart';
import '../services/creation_image.dart';
import '../services/imagine_service.dart';
import '../services/interaction_log.dart';
import '../services/scene_style.dart';
import '../services/speech.dart';
import '../services/story_store.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/board_composer.dart';
import '../widgets/quick_bar.dart';

/// The creation loop: "supported free conversation" co-creation.
///
/// Layout, top → bottom:
///  • the creation growing (the stage),
///  • the companion's message (with read-aloud) + partner tip (partner mode),
///  • either a confirmation prompt, or the tappable options + free-text input,
///  • the always-available quick-fire strip (local, no AI).
///
/// Driven by [CompanionService]; the demo passes a [MockCompanionService] so it
/// runs instantly with no backend, the real app passes ClaudeCompanionService.
class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key, required this.service, this.resumeStory});

  final CompanionService service;

  /// When set, the loop reopens THIS saved creation instead of starting
  /// from nothing — "continue from yesterday" (USER_LENS 2.4): the pieces,
  /// the pictures, and the rolling summary are seeded back in, and saving
  /// updates the same story.
  final Story? resumeStory;

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  final Speech _speech = Speech();
  final InteractionLog _log = InteractionLog();
  final TextEditingController _input = TextEditingController();
  final ScrollController _creationScroll = ScrollController();

  final List<CreationPiece> _creation = [];
  late CompanionTurn _turn;

  /// One story id per session, so pressing save again UPDATES the same
  /// saved creation instead of piling up near-duplicates. A resumed
  /// creation keeps its original id — tomorrow's work lands in the same
  /// story, not next to it.
  late final String _sessionStoryId;

  /// Rolling summary of the whole creation, maintained by the model once
  /// the creation grows long (creation_context.dart decides when only the
  /// newest pieces travel). Saved with the story for the next session.
  String? _creationSummary;

  /// A page is a few sentences with ONE picture. Pieces are grouped into
  /// pages; "דף חדש" closes the page and the next picture starts fresh —
  /// while keeping the same characters (the previous picture is the edit
  /// base). Saved stories keep one StoryPage per page.
  int _currentPage = 0;

  /// Which page each creation piece belongs to (parallel to [_creation]).
  final List<int> _piecePages = [];

  /// The picture of each page (page index → bytes).
  final Map<int, Uint8List> _sceneSnapshots = {};

  /// The picture style the creator picked (palette button); null = the
  /// model's default (soft warm illustration, per the prompt).
  SceneStyle? _sceneStyle;

  /// The model's last scene description — sent back every turn, because
  /// for a picture creation this IS the creation state (the text can be
  /// empty while a whole scene already exists).
  String? _lastScene;

  /// How many creation pieces were already saved — leaving with more than
  /// this on screen asks first (see [_confirmExit]); nothing vanishes
  /// silently.
  int _savedPieces = 0;

  /// A picture painted since the last save — a picture-only creation is a
  /// creation too, and must not vanish on exit.
  bool _sceneDirty = false;

  bool get _hasUnsaved =>
      (_creation.isNotEmpty && _savedPieces != _creation.length) ||
      _sceneDirty;

  /// The current page counts as started once it has words OR a picture.
  bool get _currentPageHasContent =>
      _piecePages.contains(_currentPage) ||
      _sceneSnapshots.containsKey(_currentPage);

  /// The scene as painted so far, when the creation is visual
  /// (scene_update in the turn contract) — the creation SEEN growing.
  Uint8List? _sceneImage;
  bool _painting = false;

  /// The visible conversation — the user's choices, the companion's
  /// replies, and each piece added to the creation. A choice that vanishes
  /// on tap leaves no sense of dialogue or authorship; the thread is where
  /// "I said → it answered → my creation grew" becomes visible.
  final List<_ThreadItem> _thread = [];
  final ScrollController _threadScroll = ScrollController();

  /// The chips in the order actually shown. A label seen before keeps its
  /// slot (motor consistency); first appearances are randomized, which keeps
  /// the position-bias signal alive. See [ChipSlots].
  final ChipSlots _chipSlots = ChipSlots();
  List<ChipOption> _displayOptions = const [];
  DateTime _optionsShownAt = DateTime.now();

  bool _busy = false;
  bool _failed = false;

  /// The raw error behind the last failure — shown small on the retry screen
  /// so remote debugging reads the cause instead of guessing it.
  String _lastError = '';
  String _lastInput = '';
  InputSource _lastSource = InputSource.user;

  bool _lowEnergy = false;
  bool _partnerMode = false;

  /// When armed (partner mode), the next tap is a partner's modelling turn —
  /// marked as such end-to-end and never treated as the user's own choice.
  bool _partnerArmed = false;

  QuickFire? _activeQuickFire;
  Timer? _quickFireTimer;

  /// The user's own imported vocabulary — lets them compose free text by
  /// tapping familiar board words instead of typing ("writing yourself"
  /// must not assume a keyboard).
  List<BoardWord> _boardWords = const [];

  /// Latencies (ms) of the user's last few selections — the live pace signal.
  /// Fast + consistent → the AI shortens or lays out; a long pause → it slows
  /// down and calms. Partner modelling taps are excluded.
  final List<int> _recentLatencies = [];

  @override
  void initState() {
    super.initState();
    final resume = widget.resumeStory;
    if (resume != null) {
      _sessionStoryId = resume.id;
      _creationSummary = resume.summary;
      for (var i = 0; i < resume.pages.length; i++) {
        final p = resume.pages[i];
        // Each saved page comes back as one piece on its own page — the
        // page structure (a few sentences + one picture) survives the
        // trip. A picture-only page seeds its picture without an empty
        // text piece.
        if (p.text.trim().isNotEmpty) {
          _creation.add(CreationPiece(
            text: p.text,
            userInput: '',
            source: InputSource.user,
            questions: p.questions,
          ));
          _piecePages.add(i);
        }
        final b64 = p.imageB64;
        if (b64 != null && b64.isNotEmpty) {
          try {
            _sceneSnapshots[i] = base64Decode(b64);
          } catch (_) {}
        }
      }
      if (resume.pages.isNotEmpty) _currentPage = resume.pages.length - 1;
      // Nothing is unsaved yet — leaving right away must not ask.
      _savedPieces = _creation.length;
      // The newest picture is the scene to keep editing from.
      if (_sceneSnapshots.isNotEmpty) {
        _sceneImage = _sceneSnapshots.entries
            .reduce((a, b) => a.key > b.key ? a : b)
            .value;
      }
      _turn = const CompanionTurn(
        say: 'חזרנו ליצירה שלך! הנה היא — ממשיכים מאיפה שעצרנו?',
        saySymbols: [
          SaySymbol(emoji: '👋', word: 'חזרנו'),
          SaySymbol(emoji: '🎨', word: 'יצירה'),
          SaySymbol(emoji: '▶️', word: 'להמשיך'),
        ],
        options: [
          ChipOption(emoji: '▶️', label: 'בואו נמשיך'),
          ChipOption(emoji: '🔊', label: 'קרא הכל'),
        ],
      );
    } else {
      _sessionStoryId = DateTime.now().microsecondsSinceEpoch.toString();
      _turn = widget.service.opening();
    }
    _thread.add(_ThreadItem.companion(_turn.say, _turn.saySymbols));
    _displayOptions = _chipSlots.arrange(_withoutStandingDoor(_turn.options));
    _optionsShownAt = DateTime.now();
    BoardStore().load().then((words) {
      if (mounted && words.isNotEmpty) setState(() => _boardWords = words);
    });
    // Silence must never be a mystery (USER_LENS 2.5): when the device
    // has no Hebrew voice at all, say so once, visibly.
    _speech.hasHebrewVoice().then((has) {
      if (has == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 6),
          content: Text('🔇 נראה שאין קול עברי במכשיר הזה — '
              'הטקסט יוצג אבל לא יוקרא.'),
        ));
      }
    });
    // Speak the opening after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak(_turn.say));
  }

  @override
  void dispose() {
    _quickFireTimer?.cancel();
    _speech.dispose();
    _input.dispose();
    _creationScroll.dispose();
    _threadScroll.dispose();
    widget.service.dispose();
    super.dispose();
  }

  void _speak(String text) => _speech.speak(text);

  String get _creationText => _creation.map((p) => p.text).join(' ');

  /// The sentences of the page being written now — what the creation card
  /// shows (a page is a few sentences with one picture).
  String get _currentPageText => [
        for (var i = 0; i < _creation.length; i++)
          if (_piecePages[i] == _currentPage) _creation[i].text,
      ].join(' ');

  /// The chips actually on screen right now (low-energy shows only 2) —
  /// the list the log must record, not the full generated set.
  List<ChipOption> get _visibleOptions =>
      _lowEnergy ? _displayOptions.take(2).toList() : _displayOptions;

  String? get _paceHint {
    if (_recentLatencies.isEmpty) return null;
    if (_recentLatencies.last > 30000) return 'hesitant';
    if (_recentLatencies.length >= 2 &&
        _recentLatencies.reversed.take(2).every((l) => l < 5000)) {
      return 'flowing';
    }
    return null;
  }

  /// The screen appends its own always-there "משהו אחר" chip (see
  /// _OptionsArea) — a model that offers one too (seen live 16.9) would
  /// put the same door on screen twice.
  static List<ChipOption> _withoutStandingDoor(List<ChipOption> options) =>
      options.where((o) => o.label.trim() != 'משהו אחר').toList();

  void _applyTurn(CompanionTurn turn, {bool speak = true}) {
    // A safeguard flag must reach a human, not only a banner: it is logged
    // and surfaces on the partner's next visit ("since your last review").
    if (turn.safeguard) unawaited(_log.logSafeguard());
    setState(() {
      _turn = turn;
      _thread.add(_ThreadItem.companion(turn.say, turn.saySymbols));
      _displayOptions = _chipSlots.arrange(_withoutStandingDoor(turn.options));
      _optionsShownAt = DateTime.now();
      _failed = false;
      _busy = false;
    });
    _scrollThreadToEnd();
    if (speak) _speak(turn.say);
  }

  Future<void> _send(
    String text, {
    required String kind, // 'chip' | 'text' | 'confirm'
    int chosenIndex = -1,
    List<String>? shownOptions,
    String emoji = '',
  }) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    _input.clear();

    // Re-reading is local: speaking what is already on screen needs no
    // model turn (and on the resumed-creation opener there IS no turn yet).
    if (t == 'קרא הכל' && _creation.isNotEmpty) {
      _speak(_creationText);
      return;
    }

    final source = _partnerArmed ? InputSource.partner : InputSource.user;
    // The choice enters the visible conversation immediately — dialogue
    // means seeing what you said, not watching it vanish.
    setState(() => _thread.add(_ThreadItem.user(t, emoji: emoji,
        isPartner: source == InputSource.partner)));
    _scrollThreadToEnd();
    final latency =
        DateTime.now().difference(_optionsShownAt).inMilliseconds;
    unawaited(_log.logSelection(
      // What was actually on screen: the visible chips, or (for a confirm
      // tap) the confirm options the caller passes in.
      shownOptions:
          shownOptions ?? _visibleOptions.map((o) => o.label).toList(),
      chosen: t,
      chosenIndex: chosenIndex,
      kind: kind,
      source: source == InputSource.partner ? 'partner' : 'user',
      lowEnergy: _lowEnergy,
      latencyMs: latency,
    ));

    if (source == InputSource.user) {
      _recentLatencies.add(latency);
      if (_recentLatencies.length > 3) _recentLatencies.removeAt(0);
    }

    setState(() => _partnerArmed = false);
    await _performTurn(t, source);
    if (mounted && _failed) _speak('רגע, משהו השתבש. אפשר לנסות שוב.');
  }

  Future<void> _retry() async {
    if (_lastInput.isEmpty || _busy) return;
    await _performTurn(_lastInput, _lastSource);
  }

  /// The visible conversation, translated for the backend: what the user and
  /// companion said recently. Without this the model has no memory at all
  /// between turns — it would lose the thread of what is being built.
  List<TurnMessage> _historyForBackend(String currentInput) {
    final items = List<_ThreadItem>.from(_thread);
    // The current input was already appended as a bubble — don't send it
    // twice (it travels separately as userInput).
    if (items.isNotEmpty &&
        (items.last.kind == _ThreadKind.user ||
            items.last.kind == _ThreadKind.partner) &&
        items.last.text == currentInput) {
      items.removeLast();
    }
    final out = <TurnMessage>[];
    for (final it in items) {
      switch (it.kind) {
        case _ThreadKind.user:
          out.add((role: 'user', text: it.text));
        case _ThreadKind.partner:
          out.add((role: 'user', text: '[הדגמה של השותף/מלווה]: ${it.text}'));
        case _ThreadKind.companion:
          out.add((role: 'assistant', text: it.text));
        case _ThreadKind.creation:
          break; // already carried by creationSoFar
      }
    }
    // The last exchanges carry the live context; older ones are reflected
    // in the creation text anyway.
    return out.length > 12 ? out.sublist(out.length - 12) : out;
  }

  /// The single turn pipeline: call the service, append the creation piece
  /// (with provenance and re-reading questions), apply the new turn.
  ///
  /// [allowCreationUpdate] is false for turns that carry no content choice
  /// of the user's (a page turn): whatever the model tried to add to the
  /// creation is dropped — words enter the creation only from HIS choices
  /// (authorship; field feedback 17.9: "it added text I didn't write").
  Future<void> _performTurn(String input, InputSource source,
      {bool allowCreationUpdate = true}) async {
    setState(() {
      _busy = true;
      _failed = false;
      _lastInput = input;
      _lastSource = source;
    });
    try {
      // A long creation travels as rolling summary + newest pieces; a
      // short one travels whole (creation_context.dart).
      final ctx = creationContext(
        [for (final p in _creation) p.text],
        _creationSummary,
      );
      final next = await widget.service.turn(
        input,
        creationSoFar: ctx.creationSoFar,
        creationSummary: ctx.creationSummary,
        sceneSoFar: _lastScene,
        history: _historyForBackend(input),
        source: source,
        lowEnergy: _lowEnergy,
        paceHint: _paceHint,
      );
      if (!mounted) return;

      final refreshed = next.creationSummary?.trim() ?? '';
      if (refreshed.isNotEmpty) _creationSummary = refreshed;

      if (allowCreationUpdate &&
          next.creationUpdate != null &&
          next.creationUpdate!.trim().isNotEmpty) {
        // Guard against the whole creation coming back as the "update"
        // (seen live 16.9 — every piece doubled on screen).
        final piece = extractNewPiece(
          next.creationUpdate!,
          [for (final p in _creation) p.text],
        );
        if (piece.isNotEmpty) {
          _creation.add(CreationPiece(
            text: piece,
            userInput: input,
            source: source,
            questions: next.questions,
          ));
          _piecePages.add(_currentPage);
          _thread.add(_ThreadItem.creation(piece));
        }
      }
      _applyTurn(next);
      _scrollCreationToEnd();
      // A visual creation paints itself as it grows — quietly, in the
      // background; the words never wait for the painter. The finished
      // picture becomes the CURRENT PAGE's picture.
      final scene = next.sceneUpdate?.trim() ?? '';
      if (scene.isNotEmpty) {
        _lastScene = scene;
        if (ImagineService.available) {
          unawaited(_paintScene(scene, forPage: _currentPage));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _lastError = e.toString();
      });
    }
  }

  /// Paints (or repaints) the scene from the companion's full description.
  /// The existing picture rides along as the edit base so the scene keeps
  /// its look between turns. Failure is quiet: the words are still there,
  /// and the next scene_update tries again.
  Future<void> _paintScene(String scene, {required int forPage}) async {
    if (_painting) return;
    setState(() => _painting = true);
    try {
      // This page's own picture is the edit base when it has one; a fresh
      // page starts from the previous picture — a NEW composition that
      // keeps the same characters (the "same character, new page" ask).
      final base = _sceneSnapshots[forPage] ?? _sceneImage;
      final freshPage = _sceneSnapshots[forPage] == null && base != null;
      final style = _sceneStyle == null ? '' : ' סגנון: ${_sceneStyle!.prompt}.';
      final prompt = freshPage
          ? 'דף חדש בסיפור: צייר סצנה חדשה — $scene. שמור בדיוק על אותן '
              'דמויות כמו בתמונה הקיימת.$style בלי טקסט בתמונה.'
          : '$scene.$style בלי טקסט בתמונה.';
      final bytes = await ImagineService().imagine(prompt, baseImage: base);
      if (!mounted) return;
      setState(() {
        _painting = false;
        _sceneImage = bytes;
        _sceneSnapshots[forPage] = bytes;
        _sceneDirty = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _painting = false);
    }
  }

  /// "דף חדש": closes the current page — the next sentences and the next
  /// picture belong to a fresh page (same characters, new scene). A real
  /// turn goes to the model so it CONTINUES the same creation on the new
  /// page (field bug 16.9: the marker alone read as "start something
  /// new" and the type menu came back).
  Future<void> _newPage() async {
    if (!_currentPageHasContent || _busy) return; // page still empty
    setState(() {
      _currentPage++;
      _thread.add(_ThreadItem.user('דף חדש', emoji: '📄'));
    });
    _scrollThreadToEnd();
    _speak('דף חדש!');
    unawaited(_log.logSelection(
      shownOptions: const [],
      chosen: 'דף חדש',
      chosenIndex: -1,
      kind: 'page',
      source: 'user',
      lowEnergy: _lowEnergy,
      latencyMs: 0,
    ));
    // A page turn is not a content choice — the model offers directions
    // for the next page, it never writes it by itself.
    await _performTurn('דף חדש', InputSource.user,
        allowCreationUpdate: false);
    if (mounted && _failed) _speak('רגע, משהו השתבש. אפשר לנסות שוב.');
  }

  /// Picking a style repaints the current picture in it; with no picture
  /// yet, the choice simply shapes every picture from here on.
  Future<void> _chooseStyle() async {
    final picked = await showModalBottomSheet<SceneStyle>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final s in kSceneStyles)
                  ChoiceChip(
                    avatar: Text(s.emoji, style: const TextStyle(fontSize: 20)),
                    label: Text(s.name, style: const TextStyle(fontSize: 16)),
                    selected: _sceneStyle == s,
                    onSelected: (_) => Navigator.of(ctx).pop(s),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _sceneStyle = picked);
    _speak(picked.name);
    if (_sceneImage != null && ImagineService.available && !_painting) {
      // Same scene, new look — repaint the current page's picture.
      setState(() => _painting = true);
      try {
        final bytes = await ImagineService().imagine(
          'אותה סצנה בדיוק, צייר את כל התמונה מחדש בסגנון: ${picked.prompt}. '
          'בלי טקסט בתמונה.',
          baseImage: _sceneImage,
        );
        if (!mounted) return;
        setState(() {
          _painting = false;
          _sceneImage = bytes;
          _sceneSnapshots[_currentPage] = bytes;
          _sceneDirty = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _painting = false);
      }
    }
  }

  /// Saves the creation so far into "my stories" — creations must never
  /// simply vanish; a finished piece is something to revisit and show.
  Future<void> _saveCreation() async {
    // Words OR pictures — a picture-only creation saves too.
    if (_creation.isEmpty && _sceneSnapshots.isEmpty) return;
    final now = DateTime.now();
    final firstWords = _creation.isEmpty
        ? 'התמונה שלי'
        : _creation.first.text.split(RegExp(r'\s+')).take(4).join(' ');
    // One StoryPage per PAGE: its few sentences joined, its questions, and
    // ITS picture (shrunk) — reading back turns the pages and watches the
    // pictures change, exactly as they were made.
    final pages = <StoryPage>[];
    for (var page = 0; page <= _currentPage; page++) {
      final texts = <String>[];
      final questions = <String>[];
      for (var i = 0; i < _creation.length; i++) {
        if (_piecePages[i] != page) continue;
        texts.add(_creation[i].text);
        questions.addAll(_creation[i].questions);
      }
      final snapshot = _sceneSnapshots[page];
      // A page earns its place with words OR a picture; only a page with
      // neither saves nothing.
      if (texts.isEmpty && snapshot == null) continue;
      pages.add(StoryPage(
        text: texts.join(' '),
        emoji: '✨',
        questions: questions,
        imageB64: snapshot == null
            ? null
            : base64Encode(await shrinkForStorage(snapshot)),
      ));
    }
    final story = Story(
      id: _sessionStoryId,
      title: firstWords.isEmpty ? 'יצירה' : firstWords,
      summary: _creationSummary,
      pages: pages,
      createdAtMs: now.millisecondsSinceEpoch,
    );
    await StoryStore().save(story);
    if (!mounted) return;
    setState(() {
      _savedPieces = _creation.length;
      _sceneDirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('נשמר ב"הסיפורים שלי" 📚')),
    );
  }

  /// Leaving with unsaved creation pieces asks first — spoken aloud, big
  /// buttons, saving as the easy default. A creation that vanishes on exit
  /// breaks "I made something — it is mine".
  Future<void> _confirmExit() async {
    if (!_hasUnsaved) {
      Navigator.of(context).pop();
      return;
    }
    _speech.speak('לשמור את היצירה לפני שיוצאים?');
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'לשמור את היצירה?',
            textAlign: TextAlign.center,
          ),
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
      await _saveCreation();
      if (mounted) Navigator.of(context).pop();
    } else if (choice == 'discard') {
      Navigator.of(context).pop();
    }
  }

  void _onQuickFire(QuickFire q) {
    // A regulation message ACTS, it doesn't only speak: everything stops
    // and the whole screen becomes the message, until the user chooses to
    // return. "Too loud" also silences and drops to low-energy first.
    _quickFireTimer?.cancel();
    if (q.label == 'חזק מדי') {
      _speech.stop();
      _lowEnergy = true;
    } else {
      _speech.stop();
      _speech.speak(q.spoken);
    }
    unawaited(_log.logQuickFire(q.label));
    setState(() => _activeQuickFire = q);
  }

  void _dismissQuickFire() {
    _speech.stop();
    setState(() => _activeQuickFire = null);
  }

  void _scrollThreadToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_threadScroll.hasClients) return;
      _threadScroll.animateTo(
        _threadScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollCreationToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_creationScroll.hasClients) {
        _creationScroll.animateTo(
          _creationScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = _visibleOptions;

    return PopScope(
      // System back with unsaved pieces goes through the same "save first?"
      // question as the arrow button — no silent loss from any exit.
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      // iOS allows speech only after it started once inside a real touch —
      // the very first tap on this screen unlocks the voice for the rest
      // of the session (Speech.warmUp self-guards to once).
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => unawaited(_speech.warmUp()),
        child: Scaffold(
      appBar: AppBar(
        title: const Text('בואו ניצור ביחד'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _confirmExit,
        ),
        actions: [
          IconButton(
            tooltip: 'סגנון התמונה',
            icon: const Icon(Icons.palette_outlined),
            onPressed: _chooseStyle,
          ),
          IconButton(
            tooltip: 'שמירת היצירה',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _creation.isEmpty && _sceneSnapshots.isEmpty
                ? null
                : _saveCreation,
          ),
          IconButton(
            tooltip: _lowEnergy ? 'חזרה למצב מלא' : 'מצב אנרגיה נמוכה',
            icon: Icon(
              _lowEnergy ? Icons.battery_charging_full : Icons.battery_saver,
            ),
            onPressed: () => setState(() => _lowEnergy = !_lowEnergy),
          ),
          IconButton(
            tooltip: _partnerMode ? 'סגירת מצב שותף' : 'מצב שותף',
            icon: Icon(
              _partnerMode ? Icons.group_rounded : Icons.group_outlined,
            ),
            onPressed: () => setState(() {
              _partnerMode = !_partnerMode;
              if (!_partnerMode) _partnerArmed = false;
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
          children: [
            if (_turn.safeguard) const _SafeguardBanner(),
            _CreationCard(
              text: _currentPageText,
              pageNumber: _currentPage > 0 ? _currentPage + 1 : null,
              scroll: _creationScroll,
              image: _sceneSnapshots[_currentPage],
              painting: _painting,
            ),
            Expanded(
              child: ListView.separated(
                controller: _threadScroll,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _thread.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ThreadBubble(
                  item: _thread[i],
                  onSpeak: _speak,
                ),
              ),
            ),
            if (_partnerMode && (_turn.partnerTip?.trim().isNotEmpty ?? false))
              _PartnerTip(text: _turn.partnerTip!.trim()),
            if (_busy)
              // Waiting is part of the experience: a calm sentence, not a
              // bare spinner — predictability is the user's regulation.
              const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'רגע, חושבים יחד… ✨',
                      style:
                          TextStyle(fontSize: 16, color: AppColors.textSoft),
                    ),
                  ],
                ),
              ),
            if (_failed)
              _RetryArea(onRetry: _retry, detail: _lastError)
            else if (_turn.needsConfirmation && _turn.confirm != null)
              _ConfirmArea(
                prompt: _turn.confirm!,
                onChoose: (o, i) => _send(
                  o,
                  kind: 'confirm',
                  chosenIndex: i,
                  shownOptions: _turn.confirm!.options,
                ),
              )
            else
              _OptionsArea(
                options: options,
                controller: _input,
                boardWords: _boardWords,
                lowEnergy: _lowEnergy,
                partnerMode: _partnerMode,
                partnerArmed: _partnerArmed,
                // "דף חדש" appears once the current page has words OR a
                // picture (a picture-only page is a page).
                onNewPage: _currentPageHasContent ? _newPage : null,
                onPartnerArmed: (v) => setState(() => _partnerArmed = v),
                onChip: (label, index) => _send(label,
                    kind: 'chip',
                    chosenIndex: index,
                    emoji: index >= 0 && index < options.length
                        ? options[index].emoji
                        : ''),
                onSubmit: (text) => _send(text, kind: 'text'),
              ),
            QuickBar(onFire: _onQuickFire),
          ],
            ),
            if (_activeQuickFire != null)
              Positioned.fill(
                child: _QuickFireOverlay(
                  fire: _activeQuickFire!,
                  onDismiss: _dismissQuickFire,
                ),
              ),
          ],
        ),
      ),
      ),
      ),
    );
  }
}

class _CreationCard extends StatelessWidget {
  const _CreationCard({
    required this.text,
    required this.scroll,
    this.image,
    this.painting = false,
    this.pageNumber,
  });

  final String text;
  final ScrollController scroll;

  /// Shown small when the creation has more than one page.
  final int? pageNumber;

  /// The painted scene of a visual creation — shown above the words.
  final Uint8List? image;

  /// A repaint is in flight (small quiet indicator on the picture).
  final bool painting;

  @override
  Widget build(BuildContext context) {
    final hasImage = image != null;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      constraints:
          BoxConstraints(minHeight: 72, maxHeight: hasImage ? 400 : 150),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        children: [
          if (pageNumber != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '📄 דף $pageNumber',
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.textSoft),
                ),
              ),
            ),
          if (hasImage) ...[
            Stack(
              children: [
                // The WHOLE picture, never a cropped strip — the scene is
                // the creation (field feedback 16.9: "the picture gets
                // cut"). Contain keeps every character in frame.
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    image!,
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
                if (painting)
                  const Positioned(
                    top: 6,
                    left: 6,
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ] else if (painting) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'מציירים את הסצנה שלך… 🎨',
                style: TextStyle(fontSize: 15, color: AppColors.textSoft),
              ),
            ),
          ],
          Expanded(
            child: text.isEmpty
                ? const Center(
                    child: Text(
                      'כאן תיבנה היצירה שלך ✨',
                      style:
                          TextStyle(fontSize: 18, color: AppColors.textSoft),
                    ),
                  )
                : SingleChildScrollView(
                    controller: scroll,
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One entry in the visible conversation.
class _ThreadItem {
  const _ThreadItem._(this.kind, this.text, this.symbols, this.emoji);

  factory _ThreadItem.companion(String say, List<SaySymbol> symbols) =>
      _ThreadItem._(_ThreadKind.companion, say, symbols, '');

  factory _ThreadItem.user(String text,
          {String emoji = '', bool isPartner = false}) =>
      _ThreadItem._(
          isPartner ? _ThreadKind.partner : _ThreadKind.user, text, const [], emoji);

  factory _ThreadItem.creation(String text) =>
      _ThreadItem._(_ThreadKind.creation, text, const [], '');

  final _ThreadKind kind;
  final String text;
  final List<SaySymbol> symbols;
  final String emoji;
}

enum _ThreadKind { user, partner, companion, creation }

/// Renders one conversation entry: the companion's bubble on one side, the
/// user's choice on the other (their color, their emoji), a partner's
/// demonstration clearly labeled, and each piece added to the creation as a
/// small highlighted moment — the dialogue made visible.
class _ThreadBubble extends StatelessWidget {
  const _ThreadBubble({required this.item, required this.onSpeak});

  final _ThreadItem item;
  final ValueChanged<String> onSpeak;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case _ThreadKind.companion:
        return _CompanionBubble(
          text: item.text,
          symbols: item.symbols,
          onSpeak: () => onSpeak(item.text),
          onSymbolTap: onSpeak,
        );
      case _ThreadKind.user:
      case _ThreadKind.partner:
        final isPartner = item.kind == _ThreadKind.partner;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isPartner)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Text(
                      'הדגמה של השותף',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textSoft),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onSpeak(item.text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(
                      color: isPartner ? AppColors.surface : AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                      border: isPartner
                          ? Border.all(color: AppColors.primary)
                          : null,
                    ),
                    child: Text(
                      item.emoji.isEmpty
                          ? item.text
                          : '${item.emoji} ${item.text}',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color:
                            isPartner ? AppColors.text : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _ThreadKind.creation:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📄 נוסף ליצירה',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  item.text,
                  style: const TextStyle(
                    fontSize: 17,
                    fontStyle: FontStyle.italic,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// The companion's message. AAC in — AAC out: when the turn carries a symbol
/// sequence, that is what the eyes read (symbol + word cards, telegraphic);
/// the full sentence stays for the speaker button. Tapping a symbol speaks
/// its word. Falls back to the plain text bubble when no symbols came.
class _CompanionBubble extends StatelessWidget {
  const _CompanionBubble({
    required this.text,
    required this.onSpeak,
    this.symbols = const [],
    this.onSymbolTap,
  });

  final String text;
  final List<SaySymbol> symbols;
  final VoidCallback onSpeak;
  final ValueChanged<String>? onSymbolTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🤖', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 8),
          // Flexible, not Expanded: the bubble hugs its words. A short
          // symbol strip inside a full-width bubble read as "half-empty"
          // on the live site (16.9).
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: symbols.isEmpty
                  ? Text(
                      text,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    )
                  // A quiet reading strip — the companion's SPEECH, styled
                  // nothing like the choice chips so it never reads as
                  // buttons to press. Tap only speaks the word.
                  : Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      children: [
                        for (final s in symbols)
                          GestureDetector(
                            onTap: onSymbolTap == null
                                ? null
                                : () => onSymbolTap!(s.word),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.emoji,
                                    style: const TextStyle(fontSize: 28)),
                                Text(
                                  s.word,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          IconButton(
            tooltip: 'הקרא',
            icon: const Icon(Icons.volume_up_rounded, color: AppColors.primary),
            onPressed: onSpeak,
          ),
        ],
      ),
    );
  }
}

/// Coaching hint for the partner — visible only in partner mode, visually
/// separate from the user's conversation.
class _PartnerTip extends StatelessWidget {
  const _PartnerTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tips_and_updates_outlined,
              size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: AppColors.textSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quick-fire message takes over the whole screen: everything pauses, the
/// message is unmissable (also to a partner across the room), and nothing
/// moves until the user chooses to return. Help/pain get the loud styling;
/// stop/break/space get a calm one.
class _QuickFireOverlay extends StatelessWidget {
  const _QuickFireOverlay({required this.fire, required this.onDismiss});

  final QuickFire fire;
  final VoidCallback onDismiss;

  bool get _urgent => fire.label == 'עזרה' || fire.label == 'כואב לי';

  @override
  Widget build(BuildContext context) {
    final bg = _urgent ? const Color(0xFFB4483C) : AppColors.primaryDark;
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: bg,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(fire.emoji, style: const TextStyle(fontSize: 96)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                fire.spoken,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              _urgent ? 'לחצו בכל מקום כשהעזרה הגיעה' : 'לחצו כשמוכנים להמשיך',
              style: TextStyle(
                fontSize: 17,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryArea extends StatelessWidget {
  const _RetryArea({required this.onRetry, this.detail = ''});

  final VoidCallback onRetry;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          const Text(
            'משהו השתבש בדרך. ננסה שוב?',
            style: TextStyle(fontSize: 18, color: AppColors.textSoft),
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
              ),
            ),
          const SizedBox(height: 10),
          BigButton(label: 'נסה שוב', emoji: '🔄', onTap: onRetry),
        ],
      ),
    );
  }
}

class _OptionsArea extends StatelessWidget {
  const _OptionsArea({
    required this.options,
    required this.controller,
    required this.boardWords,
    required this.lowEnergy,
    required this.partnerMode,
    required this.partnerArmed,
    required this.onPartnerArmed,
    required this.onChip,
    required this.onSubmit,
    this.onNewPage,
  });

  final List<ChipOption> options;
  final TextEditingController controller;
  final List<BoardWord> boardWords;
  final bool lowEnergy;
  final bool partnerMode;
  final bool partnerArmed;
  final ValueChanged<bool> onPartnerArmed;
  final void Function(String label, int index) onChip;
  final ValueChanged<String> onSubmit;

  /// Closes the current page (a few sentences + one picture) and opens the
  /// next; hidden while the current page is still empty.
  final VoidCallback? onNewPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          if (partnerMode)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChip(
                label: const Text('הדגמה של השותף'),
                avatar: const Icon(Icons.record_voice_over_outlined, size: 18),
                selected: partnerArmed,
                onSelected: onPartnerArmed,
              ),
            ),
          if (partnerMode) const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < options.length; i++)
                _Chip(
                  option: options[i],
                  big: lowEnergy,
                  onTap: () => onChip(options[i].label, i),
                ),
              // The always-there door out. Every choice set, every screen,
              // same spot: "something else" is a first-class option.
              _Chip(
                option: const ChipOption(emoji: '✨', label: 'משהו אחר'),
                big: lowEnergy,
                onTap: () => onChip('משהו אחר', -1),
              ),
              if (onNewPage != null)
                _Chip(
                  option: const ChipOption(emoji: '📄', label: 'דף חדש'),
                  big: lowEnergy,
                  onTap: onNewPage!,
                ),
            ],
          ),
          // The free-text row is hidden in low-energy mode — unless there are
          // no chips at all: never leave the user facing a dead end.
          if (!lowEnergy || options.isEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // "Writing yourself" must not assume a keyboard: the board
                // button is always there — built-in core vocabulary by
                // category, plus the user's imported board when one exists.
                BoardComposerButton(
                  words: boardWords,
                  controller: controller,
                  onSubmit: onSubmit,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: onSubmit,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      hintText: 'או כתוב/י בעצמך…',
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
                const SizedBox(width: 8),
                Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onSubmit(controller.text),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

}

class _Chip extends StatelessWidget {
  const _Chip({required this.option, required this.onTap, this.big = false});

  final ChipOption option;
  final VoidCallback onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final emojiSize = big ? 34.0 : 24.0;
    final fontSize = big ? 24.0 : 18.0;
    final pad = big
        ? const EdgeInsets.symmetric(horizontal: 26, vertical: 20)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(option.emoji, style: TextStyle(fontSize: emojiSize)),
              const SizedBox(width: 8),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmArea extends StatelessWidget {
  const _ConfirmArea({required this.prompt, required this.onChoose});

  final ConfirmPrompt prompt;
  final void Function(String option, int index) onChoose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Column(
        children: [
          Text(
            prompt.question,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < prompt.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: BigButton(
                label: prompt.options[i],
                color: AppColors.accent,
                onTap: () => onChoose(prompt.options[i], i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SafeguardBanner extends StatelessWidget {
  const _SafeguardBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3E0),
      padding: const EdgeInsets.all(12),
      child: const Text(
        'בוא נדבר על זה יחד עם מישהו שאתה סומך עליו 💛',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFFB25400),
        ),
      ),
    );
  }
}
