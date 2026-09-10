import 'dart:async';

import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/companion.dart';
import '../models/story.dart';
import '../services/board_store.dart';
import '../services/chip_layout.dart';
import '../services/companion_service.dart';
import '../services/interaction_log.dart';
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
  const CompanionScreen({super.key, required this.service});

  final CompanionService service;

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
    _turn = widget.service.opening();
    _thread.add(_ThreadItem.companion(_turn.say, _turn.saySymbols));
    _displayOptions = _chipSlots.arrange(_turn.options);
    _optionsShownAt = DateTime.now();
    BoardStore().load().then((words) {
      if (mounted && words.isNotEmpty) setState(() => _boardWords = words);
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

  void _applyTurn(CompanionTurn turn, {bool speak = true}) {
    setState(() {
      _turn = turn;
      _thread.add(_ThreadItem.companion(turn.say, turn.saySymbols));
      _displayOptions = _chipSlots.arrange(turn.options);
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

  /// The single turn pipeline: call the service, append the creation piece
  /// (with provenance and re-reading questions), apply the new turn.
  Future<void> _performTurn(String input, InputSource source) async {
    setState(() {
      _busy = true;
      _failed = false;
      _lastInput = input;
      _lastSource = source;
    });
    try {
      final next = await widget.service.turn(
        input,
        creationSoFar: _creationText,
        source: source,
        lowEnergy: _lowEnergy,
        paceHint: _paceHint,
      );
      if (!mounted) return;

      if (next.creationUpdate != null &&
          next.creationUpdate!.trim().isNotEmpty) {
        _creation.add(CreationPiece(
          text: next.creationUpdate!.trim(),
          userInput: input,
          source: source,
          questions: next.questions,
        ));
        _thread.add(_ThreadItem.creation(next.creationUpdate!.trim()));
      }
      _applyTurn(next);
      _scrollCreationToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _lastError = e.toString();
      });
    }
  }

  /// Saves the creation so far into "my stories" — creations must never
  /// simply vanish; a finished piece is something to revisit and show.
  Future<void> _saveCreation() async {
    if (_creation.isEmpty) return;
    final now = DateTime.now();
    final firstWords =
        _creation.first.text.split(RegExp(r'\s+')).take(4).join(' ');
    final story = Story(
      id: now.microsecondsSinceEpoch.toString(),
      title: firstWords.isEmpty ? 'יצירה' : firstWords,
      pages: [
        for (final p in _creation)
          StoryPage(text: p.text, emoji: '✨', questions: p.questions),
      ],
      createdAtMs: now.millisecondsSinceEpoch,
    );
    await StoryStore().save(story);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('נשמר ב"הסיפורים שלי" 📚')),
    );
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('בואו ניצור ביחד'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'שמירת היצירה',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _creation.isEmpty ? null : _saveCreation,
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
            _CreationCard(text: _creationText, scroll: _creationScroll),
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
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 3),
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
    );
  }
}

class _CreationCard extends StatelessWidget {
  const _CreationCard({required this.text, required this.scroll});

  final String text;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 72, maxHeight: 150),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: text.isEmpty
          ? const Center(
              child: Text(
                'כאן תיבנה היצירה שלך ✨',
                style: TextStyle(fontSize: 18, color: AppColors.textSoft),
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
          Expanded(
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
