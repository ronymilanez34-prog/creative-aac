import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creative_aac/models/board.dart';
import 'package:creative_aac/models/companion.dart';
import 'package:creative_aac/screens/board_create_screen.dart';
import 'package:creative_aac/services/board_mode_prefs.dart';
import 'package:creative_aac/services/companion_service.dart';
import 'package:creative_aac/services/interaction_log.dart';

/// A two-page board: home (2x2, one link to "food"), food (1x2, back home).
const _layout = BoardLayout(
  rootId: 'home',
  pages: [
    BoardPage(id: 'home', name: 'בית', rows: 2, columns: 2, buttons: [
      BoardButton(id: '1', row: 0, col: 0, label: 'שלום'),
      BoardButton(id: '2', row: 0, col: 1, label: 'אוכל', loadBoardId: 'food'),
      BoardButton(id: '3', row: 1, col: 0, label: 'כלב', speak: 'הכלב שלי'),
    ]),
    BoardPage(id: 'food', name: 'אוכל', rows: 1, columns: 2, buttons: [
      BoardButton(id: '1', row: 0, col: 0, label: 'מים', backgroundColor: '#00f'),
      BoardButton(id: '2', row: 0, col: 1, label: 'הבית', loadBoardId: 'home'),
    ]),
  ],
);

/// A companion answered by the test, recording what each turn carried.
class _Scripted implements CompanionService {
  final inputs = <String>[];
  final boardModes = <bool>[];
  final pending = <Completer<CompanionTurn>>[];

  @override
  CompanionTurn opening() => const CompanionTurn(say: 'היי');

  @override
  Future<CompanionTurn> turn(
    String userInput, {
    String creationSoFar = '',
    String? creationSummary,
    String? sceneSoFar,
    List<TurnMessage> history = const [],
    List<String> declinedOptions = const [],
    InputSource source = InputSource.user,
    bool lowEnergy = false,
    String? paceHint,
    bool boardMode = false,
  }) {
    inputs.add(userInput);
    boardModes.add(boardMode);
    final c = Completer<CompanionTurn>();
    pending.add(c);
    return c.future;
  }

  void answer(CompanionTurn t) => pending.removeAt(0).complete(t);

  @override
  void dispose() {}
}

Future<void> _pump(WidgetTester tester, CompanionService service,
    {BoardExpressionMode mode = BoardExpressionMode.immediate}) async {
  tester.view.physicalSize = const Size(1024, 1366);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  const tts = MethodChannel('flutter_tts');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(tts, (_) async => 1);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(tts, null));
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: BoardCreateScreen(service: service, layout: _layout, mode: mode),
    ),
  ));
  await tester.pump();
}

/// Lets the symbol-lighting timers run out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('the page renders in its own grid and links open pages',
      (tester) async {
    final service = _Scripted();
    await _pump(tester, service);
    await _settle(tester);

    // Home: its words in place, a link button marked, the home button idle.
    expect(find.text('שלום'), findsOneWidget);
    expect(find.text('כלב'), findsOneWidget);
    expect(find.text('אוכל'), findsWidgets);
    expect(find.text('מים'), findsNothing);
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);

    // A link opens its page — no turn is sent for navigation.
    await tester.tap(find.text('אוכל').first);
    await tester.pump();
    expect(find.text('מים'), findsOneWidget);
    expect(find.text('שלום'), findsNothing);
    expect(service.inputs, isEmpty);

    // The fixed home button goes back.
    await tester.tap(find.text('הבית').first);
    await tester.pump();
    expect(find.text('שלום'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('the grid is laid out left to right, as on the device',
      (tester) async {
    final service = _Scripted();
    await _pump(tester, service);
    await _settle(tester);
    // Home row 0: column 0 is "שלום", column 1 is "אוכל". OBF order is
    // visual left-to-right, so "שלום" must sit LEFT of "אוכל" even though
    // the app is RTL (21.10: the whole board came out mirrored).
    final left = tester.getCenter(find.text('שלום'));
    final right = tester.getCenter(find.text('אוכל').first);
    expect(left.dx, lessThan(right.dx));
    expect((left.dy - right.dy).abs(), lessThan(1));
    // Row 1 sits below row 0.
    expect(tester.getCenter(find.text('כלב')).dy, greaterThan(left.dy));
  });

  testWidgets('immediate mode: every word is a turn, flagged as board mode, and the answer comes back as board symbols',
      (tester) async {
    final service = _Scripted();
    await _pump(tester, service);
    await _settle(tester);

    await tester.tap(find.text('כלב'));
    await tester.pump();
    // The button's spoken form is what the board "says" — that is the message.
    expect(service.inputs, ['הכלב שלי']);
    expect(service.boardModes, [true]);

    service.answer(const CompanionTurn(say: 'כלב ואוכל, יופי', pageStory: 'הכלב אכל.'));
    await tester.pump();
    await _settle(tester);

    // "כלב" and "אוכל" exist on the board → their cards; "יופי" does not →
    // the bare, italic card. "ואוכל" peels its prefix to find "אוכל".
    expect(find.text('יופי'), findsOneWidget);
    expect(find.text('ואוכל'), findsOneWidget);
    expect(find.text('הכלב אכל.', skipOffstage: false), findsNothing);
    expect(find.textContaining('הכלב אכל.'), findsOneWidget);

    // The choice stands on the stage as the creation.
    expect(find.text('כלב'), findsNWidgets(3)); // the board, the stage, the strip

    // The log: a board choice, a one-word send, the companion's words sorted.
    final entries = await InteractionLog().entries();
    final choice = entries.firstWhere((e) => e['kind'] == 'board_word');
    expect(choice['source'], 'board');
    expect(choice['page'], 'home');
    expect((choice['row'], choice['col']), (1, 0));
    expect(choice['mode'], 'immediate');
    final send = entries.firstWhere((e) => e['type'] == 'board_send');
    expect(send['wordCount'], 1);
    final say = entries.lastWhere((e) => e['type'] == 'board_say');
    expect(say['fromBoard'], ['כלב', 'ואוכל']);
    expect(say['notFromBoard'], ['יופי']);
  });

  testWidgets('tray mode: words gather and "שלח" sends them as one turn',
      (tester) async {
    final service = _Scripted();
    await _pump(tester, service, mode: BoardExpressionMode.tray);
    await _settle(tester);
    expect(find.text('חלונית'), findsOneWidget);

    await tester.tap(find.text('שלום'));
    await tester.pump();
    await tester.tap(find.text('כלב'));
    await tester.pump();
    // Nothing sent yet; both words sit in the tray (board + tray = two each).
    expect(service.inputs, isEmpty);
    expect(find.text('שלום'), findsNWidgets(2));

    // "מחק" empties the tray.
    await tester.tap(find.text('מחק'));
    await tester.pump();
    expect(find.text('שלום'), findsOneWidget);

    await tester.tap(find.text('שלום'));
    await tester.pump();
    await tester.tap(find.text('כלב'));
    await tester.pump();
    await tester.tap(find.text('שלח'));
    await tester.pump();
    expect(service.inputs, ['שלום הכלב שלי']);
    expect(service.boardModes, [true]);

    final entries = await InteractionLog().entries();
    final send = entries.firstWhere((e) => e['type'] == 'board_send');
    expect(send['wordCount'], 2);
    expect(send['mode'], 'tray');
    service.answer(const CompanionTurn(say: 'שלום'));
    await _settle(tester);
  });

  test('the companion\'s words find their buttons, by phrase and by stem', () {
    const layout = BoardLayout(rootId: 'h', pages: [
      BoardPage(id: 'h', name: 'h', rows: 1, columns: 3, buttons: [
        BoardButton(id: '1', row: 0, col: 0, label: 'אני רוצה'),
        BoardButton(id: '2', row: 0, col: 1, label: 'מים'),
        BoardButton(id: '3', row: 0, col: 2, label: 'כלב'),
      ]),
    ]);
    final s = symbolsFor('אני רוצה מים, והכלב?', layout);
    expect(s.map((x) => x.word).toList(), ['אני רוצה', 'מים', 'והכלב']);
    expect(s.map((x) => x.fromBoard).toList(), [true, true, false]);
    // One prefix letter peels; two do not (ו+ה) — the honest edge.
    expect(symbolsFor('וכלב', layout).single.fromBoard, isTrue);
    expect(symbolsFor('שלום', null).single.fromBoard, isFalse);
  });

  test('board colors parse as the file writes them, never invented', () {
    expect(boardColor('#00f'), const Color(0xFF0000FF));
    expect(boardColor('#80FF00'), const Color(0xFF80FF00));
    expect(boardColor('rgb(255, 0, 0)'), const Color(0xFFFF0000));
    expect(boardColor('rgba(0,128,0,0.5)'), const Color(0xFF008000));
    expect(boardColor(''), isNull);
    expect(boardColor('blue'), isNull);
    expect(boardColor(null), isNull);
  });
}
