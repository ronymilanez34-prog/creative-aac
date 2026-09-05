import 'package:flutter/material.dart';

import '../models/board.dart';
import '../theme.dart';
import 'board_image.dart';

/// The no-keyboard way to "write it yourself": a bottom sheet of the user's
/// own imported board words. Tap adds a word to [controller], backspace
/// removes the last one, send submits. Shared by every screen with a
/// free-text field — typing is one way in, never the only one.
void showBoardComposer(
  BuildContext context, {
  required List<BoardWord> words,
  required TextEditingController controller,
  required ValueChanged<String> onSubmit,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, __) => Text(
                      value.text.isEmpty
                          ? 'לחצו על מילים כדי להרכיב משפט'
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
                IconButton(
                  tooltip: 'מחיקת המילה האחרונה',
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: () {
                    final parts = controller.text.trim().split(' ');
                    controller.text = parts.length <= 1
                        ? ''
                        : parts.sublist(0, parts.length - 1).join(' ');
                  },
                ),
                IconButton(
                  tooltip: 'שליחה',
                  icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.of(sheetContext).pop();
                    onSubmit(text);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 96,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: words.length,
                itemBuilder: (_, i) {
                  final word = words[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final current = controller.text.trim();
                      controller.text =
                          current.isEmpty ? word.label : '$current ${word.label}';
                    },
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The round board-words button that opens [showBoardComposer]. Render it
/// next to any free-text field when the user has imported vocabulary.
class BoardComposerButton extends StatelessWidget {
  const BoardComposerButton({
    super.key,
    required this.words,
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
