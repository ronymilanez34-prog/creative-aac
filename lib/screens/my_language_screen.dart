import 'package:flutter/material.dart';

import '../models/lexicon.dart';
import '../services/lexicon_store.dart';
import '../services/profile_store.dart';
import '../services/speech.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// "השפה שלנו" — the dictionary of the invented language the creator and
/// the AI grow together. Managing a language IS agency: here the creator
/// (or a partner beside them) names the language, hears every word, adds
/// words of their own, and removes words that no longer belong. Nothing
/// here is imposed; the empty state simply says where words come from.
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
    if (!mounted) return;
    setState(() {
      _lexicon = lex;
      _profileName = profile.name;
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

  /// Words can also be coined right here — with a partner, away from the
  /// creation loop. Same adoption, different door.
  Future<void> _addWord() async {
    final word = TextEditingController();
    final emoji = TextEditingController();
    final meaning = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מילה חדשה לשפה'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: word,
                autofocus: true,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(labelText: 'המילה'),
              ),
              TextField(
                controller: emoji,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(labelText: 'סמל (אימוג׳י)'),
              ),
              TextField(
                controller: meaning,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(labelText: 'מה היא אומרת'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('לשפה שלנו 🌱'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || word.text.trim().isEmpty || !mounted) return;
    final lex = await _store.adopt(LexiconWord(
      word: word.text.trim(),
      emoji: emoji.text.trim().isEmpty ? '🌱' : emoji.text.trim(),
      meaning: meaning.text.trim(),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!mounted) return;
    setState(() => _lexicon = lex);
    _speech.speak(word.text.trim());
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
                            onSpeak: () => _speech.speak(
                                w.meaning.isEmpty
                                    ? w.word
                                    : '${w.word}. ${w.meaning}'),
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
    required this.onRemove,
  });

  final LexiconWord word;
  final VoidCallback onSpeak;
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
                  ],
                ),
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
