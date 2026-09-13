import 'dart:convert';
import 'dart:typed_data';

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

  /// Decoded list thumbnails (story id → bytes), cached across rebuilds.
  final Map<String, Uint8List> _thumbCache = {};

  Uint8List? _thumb(Story s) {
    final b64 = s.pages.isNotEmpty ? s.pages.first.imageB64 : null;
    if (b64 == null || b64.isEmpty) return null;
    final bytes = _thumbCache.putIfAbsent(s.id, () {
      try {
        return base64Decode(b64);
      } catch (_) {
        return Uint8List(0);
      }
    });
    return bytes.isEmpty ? null : bytes;
  }

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
                        // The creation's own picture as the thumbnail when
                        // there is one — "find my picture" at a glance.
                        if (_thumb(s) != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _thumb(s)!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          )
                        else
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
