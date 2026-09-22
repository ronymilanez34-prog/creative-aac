import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/lexicon.dart';
import '../services/board_store.dart';
import '../services/lexicon_store.dart';
import '../services/profile_store.dart';
import '../services/speech.dart';
import '../services/voice_notes.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/board_composer.dart';
import '../widgets/voice_recorder_sheet.dart';

/// "השפה שלנו" — the dictionary of the invented language the creator and
/// the AI grow together. Managing a language IS agency: here the creator
/// (or a partner beside them) names the language, hears every word, adds
/// words of their own, and removes words that no longer belong. Nothing
/// here is imposed; the empty state simply says where words come from.
///
/// The MAIN door for someone who doesn't write is elsewhere and needs no
/// keyboard at all: the adoption card inside the creation loop
/// (companion_screen.dart) — the AI proposes a word, the creator taps
/// "yes" or "not now". This screen's own "coin a word" flow (below) exists
/// for a moment away from that loop; it still avoids a system keyboard
/// wherever the word already exists in the creator's world — a symbol
/// grid for the emoji, the board composer for the meaning — but spelling
/// a genuinely NEW word has no board to tap it from, so it uses a big
/// letter-by-letter AAC keypad instead of the phone's small keyboard.
/// Typing remains available alongside every step, never the only way in.
class MyLanguageScreen extends StatefulWidget {
  const MyLanguageScreen({super.key});

  @override
  State<MyLanguageScreen> createState() => _MyLanguageScreenState();
}

class _MyLanguageScreenState extends State<MyLanguageScreen> {
  final LexiconStore _store = LexiconStore();
  final Speech _speech = Speech();
  Lexicon _lexicon = const Lexicon();
  String _profileName = '';

  /// The creator's own imported vocabulary — feeds the no-keyboard board
  /// composer used for the new word's MEANING (an existing word can be
  /// tapped together; the invented word itself cannot, since it doesn't
  /// exist on any board yet).
  List<BoardWord> _boardWords = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _speech.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lex = await _store.load();
    final profile = await ProfileStore().load();
    final boardWords = await BoardStore().load();
    if (!mounted) return;
    setState(() {
      _lexicon = lex;
      _profileName = profile.name;
      _boardWords = boardWords;
      _loading = false;
    });
  }

  Future<void> _rename() async {
    final controller = TextEditingController(
      text: _lexicon.name.isNotEmpty
          ? _lexicon.name
          : Lexicon.suggestName(_profileName),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('איך קוראים לשפה שלכם?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(hintText: 'רוניקית, אריקית…'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('שמירה'),
            ),
          ],
        ),
      ),
    );
    if (name == null || !mounted) return;
    final lex = await _store.rename(name);
    if (!mounted) return;
    setState(() => _lexicon = lex);
    _speech.speak(lex.displayName);
  }

  /// Words can also be coined right here — away from the creation loop.
  /// Same adoption, different door: [_AddWordScreen] builds the word by
  /// tapping (letters, a symbol grid, the board composer for the meaning),
  /// never by requiring the system keyboard.
  Future<void> _addWord() async {
    final coined = await Navigator.of(context).push<LexiconWord>(
      MaterialPageRoute(
        builder: (_) => _AddWordScreen(boardWords: _boardWords),
      ),
    );
    if (coined == null || !mounted) return;
    final lex = await _store.adopt(coined);
    if (!mounted) return;
    setState(() => _lexicon = lex);
    _speech.speak(coined.word);
  }

  /// The word in its owner's voice (HANDOVER 10.9): records through the
  /// shared sheet and stores the clip on the word. From then on, speaking
  /// the word — here, and anywhere in the app via [Speech] — plays THEIR
  /// sound, not TTS.
  Future<void> _recordVoice(LexiconWord w) async {
    final clip = await showVoiceRecorderSheet(context, word: w.word);
    if (clip == null || !mounted) return;
    final lex = await _store.setVoice(w.word, clip);
    if (!mounted) return;
    setState(() => _lexicon = lex);
  }

  /// A word that already has a voice: hear / re-record / remove — the
  /// same cheap "no" the rest of the language management gives.
  Future<void> _voiceMenu(LexiconWord w) async {
    if (!w.hasVoice) {
      _recordVoice(w);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '«${w.word}» — בקול שלך',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: 'לשמוע',
                  emoji: '🔊',
                  color: AppColors.accent,
                  onTap: () => VoiceNotes.play(w.voice),
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'להקליט מחדש',
                  emoji: '🎤',
                  onTap: () => Navigator.of(ctx).pop('rerecord'),
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'למחוק את ההקלטה',
                  emoji: '🗑️',
                  color: AppColors.textSoft,
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('סגירה'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rerecord') {
      await _recordVoice(w);
    } else if (action == 'delete') {
      final lex = await _store.setVoice(w.word, '');
      if (!mounted) return;
      setState(() => _lexicon = lex);
    }
  }

  Future<void> _removeWord(LexiconWord w) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('להוציא את «${w.word}» מהשפה?'),
          content: const Text('אפשר תמיד להמציא אותה מחדש.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('להוציא'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final lex = await _store.remove(w.word);
    if (!mounted) return;
    setState(() => _lexicon = lex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🌱 ${_lexicon.displayName}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'שם לשפה',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _rename,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lexicon.isEmpty
              ? _EmptyState(onAdd: _addWord)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '${_lexicon.words.length} מילים שהמצאתם יחד — '
                        'לחיצה משמיעה, והשפה כולה שלך.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textSoft),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _lexicon.words.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final w = _lexicon.words[i];
                          return _WordCard(
                            word: w,
                            // With a recording, the card speaks the word
                            // in its owner's voice; without one, TTS reads
                            // word + meaning as before.
                            onSpeak: w.hasVoice
                                ? () => VoiceNotes.play(w.voice)
                                : () => _speech.speak(w.meaning.isEmpty
                                    ? w.word
                                    : '${w.word}. ${w.meaning}'),
                            onVoice: () => _voiceMenu(w),
                            onRemove: () => _removeWord(w),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: BigButton(
                          label: 'להמציא מילה חדשה',
                          emoji: '✨',
                          color: AppColors.accent,
                          onTap: _addWord,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({
    required this.word,
    required this.onSpeak,
    required this.onVoice,
    required this.onRemove,
  });

  final LexiconWord word;
  final VoidCallback onSpeak;
  final VoidCallback onVoice;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSpeak,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Row(
            children: [
              Text(word.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '«${word.word}»',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    if (word.meaning.isNotEmpty)
                      Text(
                        word.meaning,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textSoft),
                      ),
                    if (word.origin.isNotEmpty)
                      Text(
                        'נולדה ביצירה: ${word.origin}…',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSoft),
                      ),
                    if (word.hasVoice)
                      const Text(
                        '🎤 בקול שלך',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.primaryDark),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: word.hasVoice
                    ? 'הקול שלך על המילה'
                    : 'להקליט את המילה בקול שלך',
                icon: Icon(
                  word.hasVoice ? Icons.mic : Icons.mic_none,
                  color: word.hasVoice
                      ? AppColors.primaryDark
                      : AppColors.textSoft,
                ),
                onPressed: onVoice,
              ),
              IconButton(
                tooltip: 'להוציא מהשפה',
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.textSoft),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Hebrew alphabet (base letters, then final forms), for the
/// letter-by-letter AAC keypad — big tap targets in place of the phone's
/// small, dense system keyboard.
const _kHebrewLetters = [
  'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט', 'י', 'כ', 'ל', 'מ', 'נ', 'ס',
  'ע', 'פ', 'צ', 'ק', 'ר', 'ש', 'ת', 'ך', 'ם', 'ן', 'ף', 'ץ',
];

/// A curated, expressive set for the symbol picker — coining a NEW word has
/// no existing board button to tap for its emoji, so this stands in for
/// one: still a grid to tap, never typed.
const _kWordEmojiChoices = [
  '🌱', '✨', '💛', '🎈', '🌊', '🔥', '🐕', '🐱', '🐦', '🦋', '🌙', '☀️',
  '🌳', '🌸', '⭐', '💧', '🎵', '🎨', '🏠', '🚀', '⚡', '❄️', '🍃', '🌈',
];

/// A fresh word for the shared language, built entirely by tapping:
/// letters (spelling — no existing vocabulary can supply a NEW sound),
/// a symbol grid (the emoji), and the board composer (the meaning, which
/// CAN come from words already on the creator's board). A plain text
/// field rides alongside every step too — typing is one way in, never
/// the only one — but nothing here requires the system keyboard to pop up.
class _AddWordScreen extends StatefulWidget {
  const _AddWordScreen({required this.boardWords});

  final List<BoardWord> boardWords;

  @override
  State<_AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<_AddWordScreen> {
  final Speech _speech = Speech();
  final TextEditingController _word = TextEditingController();
  final TextEditingController _meaning = TextEditingController();
  String _emoji = '🌱';

  /// The word's sound in the creator's own voice, recorded right here —
  /// a brand-new word has no correct TTS pronunciation, so the recording
  /// can be part of coining it (and can always be added later).
  String _voice = '';

  @override
  void dispose() {
    _speech.dispose();
    _word.dispose();
    _meaning.dispose();
    super.dispose();
  }

  void _appendLetter(String letter) {
    _speech.speak(letter);
    setState(() {
      _word.text = '${_word.text}$letter';
      _word.selection =
          TextSelection.collapsed(offset: _word.text.length);
    });
  }

  void _backspace() {
    final t = _word.text;
    if (t.isEmpty) return;
    setState(() {
      _word.text = t.substring(0, t.length - 1);
      _word.selection =
          TextSelection.collapsed(offset: _word.text.length);
    });
  }

  Future<void> _pickEmoji() async {
    final picked = await showModalBottomSheet<String>(
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
                for (final e in _kWordEmojiChoices)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(ctx).pop(e),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border, width: 2),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 30)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _emoji = picked);
  }

  Future<void> _recordVoice() async {
    final word = _word.text.trim();
    final clip = await showVoiceRecorderSheet(
      context,
      word: word.isEmpty ? 'המילה החדשה' : word,
    );
    if (clip == null || !mounted) return;
    setState(() => _voice = clip);
  }

  void _done() {
    final word = _word.text.trim();
    if (word.isEmpty) return;
    Navigator.of(context).pop(LexiconWord(
      word: word,
      emoji: _emoji,
      meaning: _meaning.text.trim(),
      voice: _voice,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canFinish = _word.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('מילה חדשה לשפה'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: _pickEmoji,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.primary, width: 2),
                      ),
                      child: Text(_emoji, style: const TextStyle(fontSize: 34)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _word,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800),
                      decoration: InputDecoration(
                        hintText: 'לחצו על אותיות למטה',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    tooltip: 'השמעה',
                    icon: const Icon(Icons.volume_up_rounded,
                        color: AppColors.primary),
                    onPressed: canFinish
                        ? (_voice.isNotEmpty
                            ? () => VoiceNotes.play(_voice)
                            : () => _speech.speak(_word.text.trim()))
                        : null,
                  ),
                  IconButton(
                    tooltip: 'מחיקת אות',
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: _backspace,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(_voice.isEmpty ? Icons.mic_none : Icons.mic,
                          color: AppColors.primaryDark),
                      label: Text(
                        _voice.isEmpty
                            ? 'להקליט את המילה בקול שלך'
                            : 'המילה בקול שלך — לשמוע',
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.primaryDark),
                      ),
                      onPressed: _voice.isEmpty
                          ? _recordVoice
                          : () => VoiceNotes.play(_voice),
                    ),
                  ),
                  if (_voice.isNotEmpty) ...[
                    IconButton(
                      tooltip: 'להקליט מחדש',
                      icon: const Icon(Icons.refresh),
                      onPressed: _recordVoice,
                    ),
                    IconButton(
                      tooltip: 'למחוק את ההקלטה',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _voice = ''),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.count(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final letter in _kHebrewLetters)
                      _LetterKey(letter: letter, onTap: _appendLetter),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  BoardComposerButton(
                    words: widget.boardWords,
                    controller: _meaning,
                    onSubmit: (t) => setState(() => _meaning.text = t),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _meaning,
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        hintText: 'מה היא אומרת (או הרכיבו מהלוח)',
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: BigButton(
                label: 'לשפה שלנו',
                emoji: '🌱',
                enabled: canFinish,
                onTap: _done,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One big letter tile of the AAC spelling keypad.
class _LetterKey extends StatelessWidget {
  const _LetterKey({required this.letter, required this.onTap});

  final String letter;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(letter),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌱', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text(
                'שפה שממציאים יחד',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'תוך כדי יצירה, ה-AI יציע מדי פעם מילה חדשה —\n'
                'מילה שאין לאף אחד אחר בעולם.\n'
                'כל מילה שתאמצו תגור כאן, והשפה כולה שלך:\n'
                'לשמוע, להוסיף, להוציא — ולתת לה שם.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18, height: 1.5, color: AppColors.textSoft),
              ),
              const SizedBox(height: 32),
              BigButton(
                label: 'להמציא מילה ראשונה',
                emoji: '✨',
                onTap: onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
