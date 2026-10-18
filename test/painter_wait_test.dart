import 'package:creative_aac/widgets/painter_wait.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the brush keeps moving and never throws', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: PainterWait(paperColor: Colors.white))),
    ));
    // Several laps' worth of frames — a looping animation must stay quiet.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byType(PainterWait), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Leaving the screen disposes the ticker cleanly.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
