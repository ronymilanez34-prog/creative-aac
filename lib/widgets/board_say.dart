import 'package:flutter/material.dart';

import '../models/board.dart';
import '../services/hebrew_text.dart';
import '../theme.dart';
import 'board_image.dart';

/// The companion's words in the user's own symbols (21.10): each word of
/// `say` finds its button on the imported board and shows that picture;
/// a word the board lacks is a bare, differently styled text card — the
/// visible edge of their language. Shared by every screen that shows the
/// companion speaking.

/// One word of the companion's answer as the user sees it: with its button
/// from their board when the board has that word, bare otherwise.
class BoardSaySymbol {
  const BoardSaySymbol({required this.word, this.button});

  final String word;
  final BoardButton? button;

  bool get fromBoard => button != null;
}


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


/// One word of the companion: its board button when the board has it (the
/// picture the user knows), a bare, differently styled text card when it
/// does not — the visible edge of their language.
class BoardSaySymbolCard extends StatelessWidget {
  const BoardSaySymbolCard({super.key, required this.symbol, required this.lit});

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


/// A row of the companion's words as board symbols, [lit] the one being
/// spoken now (-1 = none). Tapping a word speaks it.
class BoardSayStrip extends StatelessWidget {
  const BoardSayStrip({
    super.key,
    required this.symbols,
    this.lit = -1,
    this.onWordTap,
  });

  final List<BoardSaySymbol> symbols;
  final int lit;
  final ValueChanged<String>? onWordTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var i = 0; i < symbols.length; i++)
          GestureDetector(
            onTap: onWordTap == null ? null : () => onWordTap!(symbols[i].word),
            child: BoardSaySymbolCard(symbol: symbols[i], lit: i == lit),
          ),
      ],
    );
  }
}

/// Lighting slots for [symbols] at the speech rate in use: when each word
/// starts, in ms from the start of speaking, and when the last one ends.
/// TODO(sync): light by the voice, not a clock. flutter_tts reports word
/// progress only on some platforms (setProgressHandler); until it is
/// wired, a slot is sized by the word's length — close enough to follow.
List<int> sayLightingSchedule(List<BoardSaySymbol> symbols) {
  final out = <int>[];
  var at = 0;
  for (final s in symbols) {
    out.add(at);
    at += 280 + 70 * s.word.length;
  }
  out.add(at + 200);
  return out;
}
