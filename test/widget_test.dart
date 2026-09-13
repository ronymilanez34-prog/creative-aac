import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creative_aac/main.dart';
import 'package:creative_aac/models/companion.dart';
import 'package:creative_aac/models/profile.dart';
import 'package:creative_aac/models/story.dart';
import 'package:creative_aac/screens/partner_screen.dart';
import 'package:creative_aac/services/chip_layout.dart';
import 'package:creative_aac/services/image_sink.dart';
import 'package:creative_aac/services/interaction_log.dart';
import 'package:creative_aac/services/obz_importer.dart';

void main() {
  testWidgets('home screen shows the calm landing actions', (tester) async {
    await tester.pumpWidget(const CreativeAacApp());

    expect(find.text('תקשורת חלופית יוצרת'), findsOneWidget);
    expect(find.text('בואו ניצור ביחד'), findsOneWidget);
    expect(find.text('בואו נבנה סיפור'), findsOneWidget);
    expect(find.text('הסיפורים שלי'), findsOneWidget);
    expect(find.text('מצב מלווה'), findsOneWidget);
  });

  testWidgets('partner screen loads the profile sections', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: PartnerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('הפרופיל האישי'), findsOneWidget);
    expect(find.text('ספריית הביטויים האישיים'), findsOneWidget);
  });

  test('profile round-trips through JSON and renders prompt text', () {
    final profile = UserProfile(
      name: 'דני',
      level: 'מילים בודדות וסמלים',
      loves: ['אוטובוסים', 'כלבים'],
      triggers: ['רעש חזק'],
      scripts: const [
        ScriptEntry(expression: 'עוד פעם שוקולד', meaning: 'אני מוצף'),
      ],
    );

    final restored = UserProfile.decode(profile.encode());
    expect(restored.name, 'דני');
    expect(restored.loves, ['אוטובוסים', 'כלבים']);
    expect(restored.scripts.single.meaning, 'אני מוצף');

    final prompt = restored.toPromptText();
    expect(prompt, contains('דני'));
    expect(prompt, contains('אוטובוסים'));
    expect(prompt, contains('עוד פעם שוקולד'));
    expect(prompt, contains('אל תתקן'));

    expect(UserProfile().toPromptText(), isEmpty);
    expect(UserProfile.decode('not json').isEmpty, isTrue);
  });

  test('companion turn survives partial and malformed JSON', () {
    // The full happy shape — mirrors the server's TURN_SCHEMA.
    final full = CompanionTurn.fromJson({
      'say': 'איזה יופי',
      'say_symbols': [
        {'emoji': '🌊', 'word': 'ים'},
        {'emoji': '❓', 'word': ''}, // empty word — filtered out
      ],
      'creation_update': 'הים היה שקט.',
      'needs_confirmation': true,
      'confirm': {
        'question': 'התכוונת לים?',
        'options': ['כן', 'לא'],
      },
      'options': [
        {'emoji': '🐟', 'label': 'דג'},
      ],
      'partner_tip': 'חכו בסבלנות',
      'questions': ['מה קרה בים?'],
      'safeguard': false,
    });
    expect(full.say, 'איזה יופי');
    expect(full.saySymbols.single.word, 'ים');
    expect(full.creationUpdate, 'הים היה שקט.');
    expect(full.needsConfirmation, isTrue);
    expect(full.confirm!.options, ['כן', 'לא']);
    expect(full.options.single.label, 'דג');
    expect(full.questions, ['מה קרה בים?']);

    // Every field missing — defaults, no crash mid-session.
    final empty = CompanionTurn.fromJson(const {});
    expect(empty.say, '');
    expect(empty.saySymbols, isEmpty);
    expect(empty.creationUpdate, isNull);
    expect(empty.needsConfirmation, isFalse);
    expect(empty.confirm, isNull);
    expect(empty.options, isEmpty);
    expect(empty.safeguard, isFalse);

    // Wrong-typed junk in list/object fields is dropped, not fatal.
    final junk = CompanionTurn.fromJson(const {
      'say': 'שלום',
      'say_symbols': ['לא אובייקט'],
      'confirm': 'לא אובייקט',
      'options': [42, null],
      'questions': ['', '  ', 'שאלה'],
    });
    expect(junk.saySymbols, isEmpty);
    expect(junk.confirm, isNull);
    expect(junk.options, isEmpty);
    expect(junk.questions, ['שאלה']);
  });

  test('story pages round-trip the real picture and can drop it', () {
    final b64 = base64Encode(Uint8List.fromList([1, 2, 3, 4]));
    final story = Story(
      id: '1',
      title: 'תמונה בים',
      createdAtMs: 0,
      pages: [StoryPage(text: 'תמונה בים.', emoji: '🖼️', imageB64: b64)],
    );

    final restored = Story.fromJson(
        jsonDecode(jsonEncode(story.toJson())) as Map<String, dynamic>);
    expect(restored.pages.single.imageB64, b64);

    // The storage-full fallback keeps the words, drops only the picture.
    final stripped = restored.withoutImages();
    expect(stripped.pages.single.imageB64, isNull);
    expect(stripped.pages.single.text, 'תמונה בים.');
    expect(stripped.title, 'תמונה בים');
  });

  test('story pages round-trip re-reading questions', () {
    const page = StoryPage(
      text: 'היה היה דרקון.',
      emoji: '🐉',
      questions: ['מי הגיבור?'],
    );
    final restored = StoryPage.fromJson(page.toJson());
    expect(restored.questions, ['מי הגיבור?']);

    // Older saved stories have no questions field — must load cleanly.
    final legacy = StoryPage.fromJson(const {'text': 'א', 'emoji': '✨'});
    expect(legacy.questions, isEmpty);
  });

  test('chip slots persist positions for repeated labels', () {
    const dog = ChipOption(emoji: '🐶', label: 'כלב');
    const sea = ChipOption(emoji: '🌊', label: 'ים');
    const cake = ChipOption(emoji: '🎂', label: 'עוגה');
    const moon = ChipOption(emoji: '🌙', label: 'ירח');

    final slots = ChipSlots();
    final first = slots.arrange(const [dog, sea, cake]);
    expect(first, hasLength(3));
    final dogSlot = first.indexWhere((o) => o.label == 'כלב');

    // The familiar chip keeps its slot on later turns, whatever else shows.
    final second = slots.arrange(const [moon, dog, sea]);
    expect(second.indexWhere((o) => o.label == 'כלב'), dogSlot);
    expect(second.map((o) => o.label).toSet(), {'ירח', 'כלב', 'ים'});

    // A remembered slot beyond the current count falls back gracefully —
    // and the original slot survives the shrink (low-energy turns must not
    // erase long-practiced positions).
    final shrunk = slots.arrange(const [dog]);
    expect(shrunk.single.label, 'כלב');
    final restored = slots.arrange(const [moon, dog, sea]);
    expect(restored.indexWhere((o) => o.label == 'כלב'), dogSlot);
  });

  test('interaction log surfaces repeated free-text as desire paths', () async {
    SharedPreferences.setMockInitialValues({});
    final log = InteractionLog();
    for (var i = 0; i < 3; i++) {
      await log.logSelection(
        shownOptions: const [],
        chosen: 'אוטובוס',
        chosenIndex: -1,
        kind: 'text',
        source: 'user',
        lowEnergy: false,
        latencyMs: 100,
      );
    }
    await log.logSelection(
      shownOptions: const ['כלב'],
      chosen: 'כלב',
      chosenIndex: 0,
      kind: 'chip',
      source: 'user',
      lowEnergy: false,
      latencyMs: 100,
    );

    final counts = await log.freeTextCounts();
    expect(counts['אוטובוס'], 3);
    expect(counts.containsKey('כלב'), isFalse);
  });

  test('obz importer parses a bare .obf board with Hebrew labels', () async {
    final obf = utf8.encode(jsonEncode({
      'format': 'open-board-0.1',
      'buttons': [
        {'id': 1, 'label': 'מים', 'vocalization': 'אני רוצה מים'},
        {'id': 2, 'label': 'כלב'},
        {'id': 3, 'label': '', 'hidden': false}, // unlabeled — skipped
        {'id': 4, 'label': 'מוסתר', 'hidden': true}, // hidden — skipped
      ],
      'grid': {
        'order': [
          [2, 1],
          [3, 4],
        ],
      },
    }));

    final result = await ObzImporter().import(
      bytes: Uint8List.fromList(obf),
      images: const NoopImageSink(),
    );

    // Grid order preserved: כלב before מים; hidden/unlabeled dropped.
    expect(result.words.map((w) => w.label).toList(), ['כלב', 'מים']);
    expect(result.words[1].spokenText, 'אני רוצה מים');
    expect(result.boardsCount, 1);

    expect(
      () => ObzImporter().import(
        bytes: Uint8List.fromList(utf8.encode('not a board')),
        images: const NoopImageSink(),
      ),
      throwsA(isA<ObzFormatException>()),
    );
  });
}
