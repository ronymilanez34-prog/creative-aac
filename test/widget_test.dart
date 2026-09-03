import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creative_aac/main.dart';
import 'package:creative_aac/models/companion.dart';
import 'package:creative_aac/models/profile.dart';
import 'package:creative_aac/models/story.dart';
import 'package:creative_aac/screens/partner_screen.dart';
import 'package:creative_aac/services/chip_layout.dart';
import 'package:creative_aac/services/interaction_log.dart';

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
}
