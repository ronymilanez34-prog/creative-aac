import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creative_aac/main.dart';
import 'package:creative_aac/models/profile.dart';
import 'package:creative_aac/models/story.dart';
import 'package:creative_aac/screens/partner_screen.dart';

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
}
