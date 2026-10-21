import 'package:flutter/material.dart';

import '../models/board.dart';
import '../theme.dart';
import 'board_image.dart';
import 'sturdy_tap.dart';

/// The user's own board on screen, exactly as they know it (21.10):
/// a page in its grid, a tray that collects words until "שלח", the home
/// button. Shared by "יוצרים מהלוח שלי" and by the companion screen, so
/// the board behaves the same wherever it appears.

/// A board color as the file writes it: "#rgb", "#rrggbb", "rgb(r, g, b)"
/// or "rgba(r, g, b, a)". Null when absent or unreadable — then the cell
/// gets the plain surface, never an invented color.
Color? boardColor(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().toLowerCase();
  if (s.startsWith('#')) {
    var hex = s.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length != 6) return null;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
  final m = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(s);
  if (m == null) return null;
  return Color.fromARGB(255, int.parse(m[1]!).clamp(0, 255),
      int.parse(m[2]!).clamp(0, 255), int.parse(m[3]!).clamp(0, 255));
}


class BoardSymbolCard extends StatelessWidget {
  const BoardSymbolCard({super.key, required this.label, this.imagePath, this.size = 40});

  final String label;
  final String? imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imagePath != null) BoardImage(imagePath: imagePath, emoji: '', size: size),
          Text(label,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
        ],
      ),
    );
  }
}

/// The user's board: tray (in tray mode), the page's name and the home
/// button, then the page in its own grid.
class BoardPanel extends StatelessWidget {
  const BoardPanel({
    super.key,
    required this.page,
    required this.isHome,
    this.tray,
    this.modeLabel = '',
    this.gridHeight,
    required this.onButton,
    required this.onHome,
    required this.onSend,
    required this.onClear,
  });

  final BoardPage page;
  final bool isHome;

  /// The words gathered so far; null hides the tray (every press is sent
  /// by the caller at once).
  final List<BoardButton>? tray;

  /// Small text at the corner (the expression pattern), or ''.
  final String modeLabel;

  /// Fixed height for the grid when the panel sits inside a scroll view;
  /// null lets it fill the available space.
  final double? gridHeight;
  final ValueChanged<BoardButton> onButton;
  final VoidCallback onHome;
  final VoidCallback onSend;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tray != null)
            BoardTray(words: tray!, onSend: onSend, onClear: onClear),
          Row(
            children: [
              Semantics(
                button: true,
                label: 'דף הבית',
                child: Material(
                  color: isHome
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isHome ? null : onHome,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home_rounded, size: 22, color: AppColors.text),
                          SizedBox(width: 6),
                          Text('הבית',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  page.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: AppColors.textSoft),
                ),
              ),
              Text(
                modeLabel,
                style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (gridHeight != null)
            SizedBox(height: gridHeight, child: BoardGrid(page: page, onButton: onButton))
          else
            Expanded(child: BoardGrid(page: page, onButton: onButton)),
        ],
      ),
    );
  }
}

/// The message window of a board that collects before it speaks.
class BoardTray extends StatelessWidget {
  const BoardTray({super.key, required this.words, required this.onSend, required this.onClear});

  final List<BoardButton> words;
  final VoidCallback onSend;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: words.isEmpty
                ? const Text('לחצו על מילים, ואז "שלח"',
                    style: TextStyle(fontSize: 15, color: AppColors.textSoft))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final b in words)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: BoardSymbolCard(
                                label: b.label, imagePath: b.imagePath, size: 32),
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: words.isEmpty ? null : onSend,
            icon: const Icon(Icons.send_rounded, size: 20),
            label: const Text('שלח', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: words.isEmpty ? null : onClear,
            child: const Text('מחק'),
          ),
        ],
      ),
    );
  }
}

/// The page exactly as its grid: equal cells, same rows and columns, empty
/// cells left empty — a finger that knows the way finds the same place.
///
/// OBF's grid.order is visual, left to right: column 0 is the LEFTMOST
/// cell on the user's device. The app lays everything out right to left
/// (Hebrew), which mirrored the whole board (iPad, 21.10). The grid is
/// therefore laid out left to right on purpose; the text inside each
/// button stays right to left.
class BoardGrid extends StatelessWidget {
  const BoardGrid({super.key, required this.page, required this.onButton});

  final BoardPage page;
  final ValueChanged<BoardButton> onButton;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          for (var r = 0; r < page.rows; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < page.columns; c++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child:
                              _BoardCell(button: page.at(r, c), onButton: onButton),
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

class _BoardCell extends StatelessWidget {
  const _BoardCell({required this.button, required this.onButton});

  final BoardButton? button;
  final ValueChanged<BoardButton> onButton;

  @override
  Widget build(BuildContext context) {
    final b = button;
    if (b == null) return const SizedBox.expand();
    final bg = boardColor(b.backgroundColor) ?? AppColors.surface;
    final dark = bg.computeLuminance() < 0.4;
    final fg = dark ? Colors.white : AppColors.text;
    return Semantics(
      button: true,
      label: b.isLink ? 'פתיחת ${b.label}' : b.spokenText,
      child: SturdyTap(
        onTap: () => onButton(b),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: LayoutBuilder(builder: (context, c) {
            final imgSize = (c.maxHeight * 0.5).clamp(16.0, 72.0);
            return Stack(
              children: [
                // As on TouchChat: the label ABOVE the picture. A button
                // with a picture and no label (an arrow, a person) shows
                // the picture alone.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (b.label.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              b.label,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                      if (b.imagePath != null)
                        BoardImage(imagePath: b.imagePath, emoji: '', size: imgSize)
                      else if (b.imageFile != null)
                        // The file had a picture here but it did not
                        // survive storage — visible, never silent.
                        Icon(Icons.image_not_supported_outlined,
                            size: imgSize * 0.6, color: fg.withValues(alpha: 0.5)),
                    ],
                  ),
                ),
                if (b.isLink)
                  Positioned(
                    top: 3,
                    left: 3,
                    child: Icon(Icons.folder_open_rounded,
                        size: 14, color: fg.withValues(alpha: 0.7)),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

