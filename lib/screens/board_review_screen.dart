import 'package:flutter/material.dart';

import '../services/board_reader_service.dart';
import '../theme.dart';
import '../widgets/big_button.dart';

/// The staff check the words the AI read off a board BEFORE they become the
/// friend's words: the model proposes, a person decides.
///
/// One tap takes a word out (and back in). Words the AI was unsure of carry
/// a "?" and a warm border so they get a second look. Nothing is saved until
/// "לשמור". Pops with the kept labels, or null when cancelled.
class BoardReviewScreen extends StatefulWidget {
  const BoardReviewScreen({super.key, required this.words});

  final List<ReadWord> words;

  @override
  State<BoardReviewScreen> createState() => _BoardReviewScreenState();
}

class _BoardReviewScreenState extends State<BoardReviewScreen> {
  late final List<bool> _keep = List.filled(widget.words.length, true);

  static const _unsure = Color(0xFFD9A441);

  int get _kept => _keep.where((k) => k).length;

  @override
  Widget build(BuildContext context) {
    final unsure = widget.words.where((w) => !w.sure).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('בדיקת המילים'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'ביטול',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'ה-AI קרא ${widget.words.length} מילים מהלוח.\n'
              'לחיצה על מילה מוציאה אותה (לחיצה נוספת מחזירה).'
              '${unsure > 0 ? '\nמילים עם ? — ה-AI לא היה בטוח בהן. כדאי לבדוק.' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, height: 1.5, color: AppColors.textSoft),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < widget.words.length; i++) _chip(i),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: BigButton(
                label: 'לשמור $_kept מילים',
                emoji: '✅',
                enabled: _kept > 0,
                onTap: () {
                  if (_kept == 0) return;
                  Navigator.of(context).pop([
                    for (var i = 0; i < widget.words.length; i++)
                      if (_keep[i]) widget.words[i].label,
                  ]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(int i) {
    final w = widget.words[i];
    final kept = _keep[i];
    return Semantics(
      button: true,
      selected: kept,
      label: kept ? w.label : '${w.label} — הוצא',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _keep[i] = !kept),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: kept ? AppColors.surface : AppColors.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: !kept ? AppColors.border : (w.sure ? AppColors.primary : _unsure),
              width: 2,
            ),
          ),
          child: Text(
            '${w.label}${w.sure ? '' : ' ?'}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: kept ? AppColors.text : AppColors.textSoft,
              decoration: kept ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }
}
