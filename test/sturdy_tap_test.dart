import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:creative_aac/widgets/sturdy_tap.dart';

void main() {

  testWidgets('a clean tap fires once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SturdyTap(
          onTap: () => taps++,
          child: const SizedBox(width: 200, height: 100),
        ),
      ),
    ));
    await tester.tap(find.byType(SturdyTap));
    expect(taps, 1);
  });

  testWidgets('a wobbling finger (30px drift) still counts; a 100px drag does not',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SturdyTap(
          onTap: () => taps++,
          child: const SizedBox(width: 200, height: 100),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(SturdyTap));
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(20, 22));
    await g.up();
    expect(taps, 1, reason: 'drift under the slop is a press');

    final g2 = await tester.startGesture(center);
    await g2.moveBy(const Offset(0, -90));
    await g2.up();
    expect(taps, 1, reason: 'a long drag is a scroll, not a press');

    // Release outside the widget: not a press either.
    final g3 = await tester.startGesture(center + const Offset(90, 40));
    await g3.moveBy(const Offset(30, 30));
    await g3.up();
    expect(taps, 1);
  });

  testWidgets('two fingers never press', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SturdyTap(
          onTap: () => taps++,
          child: const SizedBox(width: 200, height: 100),
        ),
      ),
    ));
    final c = tester.getCenter(find.byType(SturdyTap));
    final a = await tester.startGesture(c, pointer: 1);
    final b = await tester.startGesture(c + const Offset(10, 0), pointer: 2);
    await a.up();
    await b.up();
    expect(taps, 0);
  });
}
