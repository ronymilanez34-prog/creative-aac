import 'package:flutter/material.dart';

import '../data/core_vocabulary.dart';
import '../models/board.dart';
import '../services/speech.dart';
import '../theme.dart';
import 'board_image.dart';

/// The no-keyboard way to "write it yourself": a bottom sheet organized
/// like a communication board — picture categories that open into related
/// words. Always available (built-in core vocabulary); an imported board
/// appears as its own first category. Tap adds a word, backspace removes
/// the last one, send submits. Typing is one way in, never the only one.
/// [addEachWord]: every word tap submits immediately (no sentence bar, no
/// send arrow) and the sheet stays open for more — the right mode when each
/// word IS the action, like dropping things onto a picture.
void showBoardComposer(
  BuildContext context, {
  List<BoardWord> words = const [],
  required TextEditingController controller,
  required ValueChanged<String> onSubmit,
  bool addEachWord = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _BoardComposerSheet(
      imported: words,
      controller: controller,
      onSubmit: onSubmit,
      addEachWord: addEachWord,
    ),
  );
}

class _BoardComposerSheet extends StatefulWidget {
  const _BoardComposerSheet({
    required this.imported,
    required this.controller,
    required this.onSubmit,
    this.addEachWord = false,
  });

  final List<BoardWord> imported;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final bool addEachWord;

  @override
  State<_BoardComposerSheet> createState() => _BoardComposerSheetState();
}

class _BoardComposerSheetState extends State<_BoardComposerSheet> {
  final Speech _speech = Speech();

  /// null = category grid; -1 = the imported board; otherwise an index
  /// into [kCoreVocabulary].
  int? _open;

  @override
  void dispose() {
    _speech.dispose();
    super.dispose();
  }

  /// Adds [label] to the sentence and speaks the right thing: an imported
  /// button's spoken form when it has one ("מים" may speak "אני רוצה מים"),
  /// otherwise the label itself. Every tap is heard — auditory feedback is
  /// part of AAC, not a nicety.
  void _addWord(String label, {String? speak}) {
    if (widget.addEachWord) {
      // Each tap IS the action — submit now, stay open for the next one.
      // The caller gives the feedback (speech, the thing landing).
      widget.onSubmit(label);
      return;
    }
    _speech.speak(speak ?? label);
    final current = widget.controller.text.trim();
    widget.controller.text = current.isEmpty ? label : '$current $label';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_open != null)
                  IconButton(
                    tooltip: 'חזרה לקטגוריות',
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () => setState(() => _open = null),
                  ),
                Expanded(
                  child: widget.addEachWord
                      ? const Text(
                          'כל לחיצה מוסיפה לתמונה ✨',
                          style: TextStyle(
                              fontSize: 18, color: AppColors.textSoft),
                        )
                      : ValueListenableBuilder<TextEditingValue>(
                          valueListenable: widget.controller,
                          builder: (_, value, __) => Text(
                            value.text.isEmpty
                                ? 'לחצו על תמונות כדי להרכיב משפט'
                                : value.text,
                            style: TextStyle(
                              fontSize: 18,
                              color: value.text.isEmpty
                                  ? AppColors.textSoft
                                  : AppColors.text,
                            ),
                          ),
                        ),
                ),
                if (widget.addEachWord)
                  IconButton(
                    tooltip: 'סיימנו',
                    icon: const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                else ...[
                  IconButton(
                    tooltip: 'מחיקת המילה האחרונה',
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: () {
                      final parts = widget.controller.text.trim().split(' ');
                      widget.controller.text = parts.length <= 1
                          ? ''
                          : parts.sublist(0, parts.length - 1).join(' ');
                    },
                  ),
                  IconButton(
                    tooltip: 'שליחה',
                    icon: const Icon(Icons.send_rounded,
                        color: AppColors.primary),
                    onPressed: () {
                      final text = widget.controller.text.trim();
                      if (text.isEmpty) return;
                      Navigator.of(context).pop();
                      widget.onSubmit(text);
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Flexible(child: _open == null ? _categories() : _words()),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _categories() {
    final tiles = <Widget>[
      if (widget.imported.isNotEmpty)
        _tile('⭐', 'הלוח שלי', () {
          _speech.speak('הלוח שלי');
          setState(() => _open = -1);
        }),
      for (var i = 0; i < kCoreVocabulary.length; i++)
        _tile(kCoreVocabulary[i].emoji, kCoreVocabulary[i].name, () {
          _speech.speak(kCoreVocabulary[i].name);
          setState(() => _open = i);
        }),
    ];
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: tiles,
    );
  }

  Widget _words() {
    if (_open == -1) {
      return GridView.builder(
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 96,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: widget.imported.length,
        itemBuilder: (_, i) {
          final word = widget.imported[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _addWord(word.label, speak: word.spokenText),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BoardImage(imagePath: word.imagePath, size: 40),
                const SizedBox(height: 4),
                Text(
                  word.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        },
      );
    }
    final cat = kCoreVocabulary[_open!];
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 96,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: cat.words.length,
      itemBuilder: (_, i) {
        final w = cat.words[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _addWord(w.label),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(w.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(height: 2),
              Text(
                w.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(String emoji, String name, VoidCallback onTap) {
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
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round board button that opens [showBoardComposer]. Always shown next
/// to a free-text field — the built-in core board needs no import.
class BoardComposerButton extends StatelessWidget {
  const BoardComposerButton({
    super.key,
    this.words = const [],
    required this.controller,
    required this.onSubmit,
  });

  final List<BoardWord> words;
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showBoardComposer(
          context,
          words: words,
          controller: controller,
          onSubmit: onSubmit,
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.apps_rounded, color: AppColors.text),
        ),
      ),
    );
  }
}
