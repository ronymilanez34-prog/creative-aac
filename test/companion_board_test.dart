import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creative_aac/models/board.dart';
import 'package:creative_aac/models/companion.dart';
import 'package:creative_aac/screens/companion_screen.dart';
import 'package:creative_aac/services/companion_service.dart';
import 'package:creative_aac/services/interaction_log.dart';

/// The user's own board inside the creation loop (21.10, Rony): "press a
/// few things and send, so Paz reads it all as one chunk".
const _layout = BoardLayout(
  rootId: 'home',
  pages: [
    BoardPage(id: 'home', name: 'בית', rows: 2, columns: 2, buttons: [
      BoardButton(id: '1', row: 0, col: 0, label: 'שלום'),
      BoardButton(id: '2', row: 0, col: 1, label: 'אוכל', loadBoardId: 'food'),
      BoardButton(id: '3', row: 1, col: 0, label: 'כלב', speak: 'הכלב שלי'),
    ]),
    BoardPage(id: 'food', name: 'אוכל', rows: 1, columns: 1, buttons: [
      BoardButton(id: '1', row: 0, col: 0, label: 'מים'),
    ]),
  ],
);

const _chips = [
  ChipOption(emoji: '📖', label: 'סיפור'),
  ChipOption(emoji: '🎵', label: 'שיר'),
];

class _Scripted implements CompanionService {
  final inputs = <String>[];
  final pending = <Completer<CompanionTurn>>[];

  @override
  CompanionTurn opening() => const CompanionTurn(say: 'היי', options: _chips);

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
    final c = Completer<CompanionTurn>();
    pending.add(c);
    return c.future;
  }

  void answer(CompanionTurn t) => pending.removeAt(0).complete(t);

  @override
  void dispose() {}
}

Future<void> _pump(WidgetTester tester, CompanionService service) async {
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
      child: CompanionScreen(service: service, boardLayout: _layout),
    ),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('the board sits under the chips; words gather and "שלח" sends one input',
      (tester) async {
    final service = _Scripted();
    await _pump(tester, service);
    await _settle(tester);

    // Chips and the board, both on screen; typing steps aside.
    expect(find.text('סיפור'), findsOneWidget);
    expect(find.text('שלום'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('שלום'));
    await tester.pump();
    await tester.tap(find.text('כלב'));
    await tester.pump();
    // Nothing sent yet — both wait in the tray (board + tray = two each).
    expect(service.inputs, isEmpty);
    expect(find.text('שלום'), findsNWidgets(2));

    await tester.tap(find.text('שלח'));
    await tester.pump();
    // One input, the whole chunk, in the board's own spoken words.
    expect(service.inputs, ['שלום הכלב שלי']);
    // The tray is empty again; the chunk stands in the conversation.
    expect(find.text('שלום'), findsOneWidget);
    expect(find.text('שלום הכלב שלי'), findsWidgets);

    service.answer(const CompanionTurn(say: 'כלב ומים, יופי', options: _chips));
    await _settle(tester);
    // Paz speaks in the board's symbols: "יופי" is not on the board — a
    // bare card; "ומים" peels to "מים"; "כלב" has its button.
    expect(find.text('יופי'), findsOneWidget);
    expect(find.text('ומים'), findsOneWidget);
    final say = (await InteractionLog().entries()).lastWhere((e) => e['type'] == 'board_say');
    expect(say['fromBoard'], ['כלב', 'ומים']);
    expect(say['notFromBoard'], ['יופי']);

    // Navigation on the board still works inside the loop.
    await tester.tap(find.text('אוכל'));
    await tester.pump();
    expect(find.text('מים'), findsOneWidget);
    await tester.tap(find.text('הבית'));
    await tester.pump();
    expect(find.text('שלום'), findsOneWidget);

    final entries = await InteractionLog().entries();
    expect(entries.where((e) => e['kind'] == 'board_word').length, 2);
    final send = entries.firstWhere((e) => e['type'] == 'board_send');
    expect(send['wordCount'], 2);
    expect(entries.where((e) => e['kind'] == 'board').length, 1);
  });

  testWidgets('a chip still works next to the board', (tester) async {
    final service = _Scripted();
    await _pump(tester, service);
    await _settle(tester);
    await tester.tap(find.text('שיר'));
    await tester.pump();
    expect(service.inputs, ['שיר']);
    service.answer(const CompanionTurn(say: 'שיר!', options: _chips));
    await _settle(tester);
  });
}
