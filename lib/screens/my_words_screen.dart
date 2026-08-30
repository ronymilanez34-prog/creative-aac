import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/board.dart';
import '../services/board_store.dart';
import '../services/obz_importer.dart';
import '../theme.dart';
import '../widgets/big_button.dart';
import '../widgets/board_image.dart';

/// "המילים שלי" — import the user's own vocabulary from their AAC app.
///
/// Deliberately one-tap simple: parents and facilitators are not technical,
/// and this flow is the front door for every existing AAC user. Empty state
/// explains what to do in plain words; after import, the screen shows the
/// familiar words and pictures so the parent can immediately see it worked.
class MyWordsScreen extends StatefulWidget {
  const MyWordsScreen({super.key});

  @override
  State<MyWordsScreen> createState() => _MyWordsScreenState();
}

class _MyWordsScreenState extends State<MyWordsScreen> {
  final BoardStore _store = BoardStore();
  List<BoardWord> _words = [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final words = await _store.load();
    if (!mounted) return;
    setState(() {
      _words = words;
      _loading = false;
    });
  }

  Future<void> _pickAndImport() async {
    if (_importing) return;

    // FileType.any (not custom extensions) — iOS document pickers are
    // unreliable with unregistered extensions like .obz; we validate content.
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;

    setState(() => _importing = true);
    try {
      final result = await _store.importFromBytes(bytes);
      if (!mounted) return;
      setState(() {
        _words = result.words;
        _importing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'יובאו ${result.words.length} מילים ו-${result.imagesCount} תמונות 🎉',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      final msg = e is ObzFormatException ? e.message : 'משהו השתבש בייבוא — נסו שוב';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('למחוק את המילים שיובאו?'),
        content: const Text('אפשר תמיד לייבא שוב מקובץ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.clear();
    if (!mounted) return;
    setState(() => _words = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('המילים שלי'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_words.isNotEmpty)
            IconButton(
              tooltip: 'מחק את המילים שיובאו',
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _words.isEmpty
              ? _EmptyState(importing: _importing, onImport: _pickAndImport)
              : _WordsGrid(
                  words: _words,
                  importing: _importing,
                  onImport: _pickAndImport,
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.importing, required this.onImport});

  final bool importing;
  final VoidCallback onImport;

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
              const Text('💬', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text(
                'המילים המוכרות — גם כאן',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'משתמשים כבר באפליקציית תקשורת?\n'
                'ייצאו ממנה קובץ לוח (‎.obz) וייבאו אותו לכאן —\n'
                'המילים והתמונות המוכרות יופיעו גם ביצירת הסיפורים.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, height: 1.5, color: AppColors.textSoft),
              ),
              const SizedBox(height: 32),
              if (importing)
                const CircularProgressIndicator()
              else
                BigButton(
                  label: 'בחירת קובץ לייבוא',
                  emoji: '📂',
                  onTap: onImport,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordsGrid extends StatelessWidget {
  const _WordsGrid({
    required this.words,
    required this.importing,
    required this.onImport,
  });

  final List<BoardWord> words;
  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: words.length,
            itemBuilder: (context, i) {
              final w = words[i];
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: BoardImage(imagePath: w.imagePath, emoji: '💬', size: 44),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      w.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: importing
                ? const CircularProgressIndicator()
                : BigButton(
                    label: 'ייבוא קובץ אחר',
                    emoji: '📂',
                    color: AppColors.accent,
                    onTap: onImport,
                  ),
          ),
        ),
      ],
    );
  }
}
