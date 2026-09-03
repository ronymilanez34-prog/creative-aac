import 'package:flutter_test/flutter_test.dart';

import 'package:creative_aac/main.dart';

void main() {
  testWidgets('home screen shows the calm landing actions', (tester) async {
    await tester.pumpWidget(const CreativeAacApp());

    expect(find.text('תקשורת חלופית יוצרת'), findsOneWidget);
    expect(find.text('בואו ניצור ביחד'), findsOneWidget);
    expect(find.text('בואו נבנה סיפור'), findsOneWidget);
    expect(find.text('הסיפורים שלי'), findsOneWidget);
  });
}
