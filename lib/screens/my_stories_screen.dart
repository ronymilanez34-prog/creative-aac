import 'package:flutter/material.dart';

import '../models/story.dart';
import '../services/story_store.dart';
import '../theme.dart';
import 'story_view_screen.dart';

/// Lists the stories the user has saved. Tap to read again; long-press or the
/// delete icon to remove.
class MyStoriesScreen extends StatefulWidget {
  const MyStoriesScreen({super.key});

  @override
  State<MyStoriesScreen> createState() => _MyStoriesScreenState();
}

class _MyStoriesScreenState extends State<MyStoriesScreen> {
  final StoryStore _store = StoryStore();
  late Future<List<Story>> _future;

  @override
  void initState() {
    super.initState();
    _future = _store.loadAll();
  }

  void _reload() => setState(() => _future = _store.loadAll());

  Future<void> _delete(Story s) async {
    await _store.delete(s.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('הסיפורים שלי'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FutureBuilder<List<Story>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final stories = snapshot.data ?? const [];
          if (stories.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('📚', style: TextStyle(fontSize: 64)),
                    SizedBox(height: 16),
                    Text(
                      'עדיין אין סיפורים שמורים.\nבנו סיפור ראשון!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, color: AppColors.textSoft),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final s = stories[i];
              return Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StoryViewScreen(story: s),
                      ),
                    );
                    _reload();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text(
                          s.pages.isNotEmpty ? s.pages.first.emoji : '📖',
                          style: const TextStyle(fontSize: 40),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            s.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.textSoft),
                          onPressed: () => _delete(s),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
