import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:creative_aac/models/companion.dart';
import 'package:creative_aac/screens/companion_screen.dart';
import 'package:creative_aac/services/companion_service.dart';
import 'package:creative_aac/services/imagine_service.dart';
import 'package:creative_aac/services/scene_style.dart';
import 'package:creative_aac/widgets/chosen_pictos.dart';

/// A 1x1 transparent PNG — valid bytes for Image.memory; each paint gets
/// its own copy so pictures can be told apart by identity.
final _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
Uint8List _picture() => Uint8List.fromList(_png);

const _chips = [
  ChipOption(emoji: '🖼️', label: 'תמונה'),
  ChipOption(emoji: '🐶', label: 'כלב'),
  ChipOption(emoji: '🌳', label: 'עץ'),
  ChipOption(emoji: '👩', label: 'אמא'),
];

/// A companion whose every turn is answered by the test, when the test
/// says — so the order of "answer arrives" vs "picture arrives" is chosen.
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

/// The painter, under the test's control the same way.
class _Painter {
  final prompts = <String>[];
  final bases = <Uint8List?>[];
  final pending = <Completer<Uint8List>>[];

  Future<Uint8List> call(String prompt, {Uint8List? baseImage}) {
    prompts.add(prompt);
    bases.add(baseImage);
    final c = Completer<Uint8List>();
    pending.add(c);
    return c.future;
  }

  Uint8List finish() {
    final bytes = _picture();
    pending.removeAt(0).complete(bytes);
    return bytes;
  }
}

Uint8List? _shownPicture(WidgetTester tester) {
  final images = tester.widgetList<Image>(find.byType(Image));
  for (final img in images) {
    final provider = img.image;
    if (provider is MemoryImage) return provider.bytes;
  }
  return null;
}

Future<void> _pumpScreen(WidgetTester tester, CompanionService service,
    {Size size = const Size(1024, 1366)}) async {
  // The pilot's screen: an iPad in portrait (or, when asked, landscape
  // inside Safari, with far less height).
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  // The screen speaks on every tap; the TTS plugin has no test host.
  const tts = MethodChannel('flutter_tts');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(tts, (_) async => 1);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(tts, null));
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: CompanionScreen(service: service),
    ),
  ));
  await tester.pump();
}

/// Lets a bounded amount of time pass without waiting for animations to
/// end — the pictograms breathe forever while they stand. The edit base
/// is shrunk with a real image decode, which only real time completes.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  tearDown(() => ImagineService.override = null);

  testWidgets('a tapped chip stands big on the stage until the turn ends without a picture',
      (tester) async {
    final service = _Scripted();
    await _pumpScreen(tester, service);
    expect(find.byType(ChosenPictos), findsNothing);

    await tester.tap(find.text('כלב'));
    await tester.pump();
    // At once, before any answer: the choice is on the stage.
    expect(find.byType(ChosenPictos), findsOneWidget);
    expect(service.inputs, ['כלב']);

    // A words-only turn (no scene, no painter): the stage clears.
    service.answer(const CompanionTurn(say: 'כלב!', creationUpdate: 'כלב', options: _chips));
    await _settle(tester);
    expect(find.byType(ChosenPictos), findsNothing);
  });

  testWidgets('the first picture waits for the model; from the second on the paint starts at the tap',
      (tester) async {
    final service = _Scripted();
    final painter = _Painter();
    ImagineService.override = painter.call;
    await _pumpScreen(tester, service);

    // 1. First content choice: no scene yet → nothing speculative.
    await tester.tap(find.text('כלב'));
    await tester.pump();
    expect(painter.prompts, isEmpty);
    service.answer(const CompanionTurn(
        say: 'כלב', creationUpdate: 'כלב', sceneUpdate: 'כלב על דשא', options: _chips));
    await _settle(tester);
    expect(painter.prompts.length, 1, reason: 'serial paint after the answer');
    expect(painter.bases.single, isNull);
    // The pictogram stands over the empty stage while the first picture paints.
    expect(find.byType(ChosenPictos), findsOneWidget);
    final first = painter.finish();
    await _settle(tester);
    expect(identical(_shownPicture(tester), first), isTrue);
    expect(find.byType(ChosenPictos), findsNothing);

    // The app's own style question follows the first picture — answer it.
    await tester.tap(find.text('🎨 ציור רך'));
    await tester.pump();
    expect(painter.prompts.length, 2, reason: 'restyle paint');
    service.answer(const CompanionTurn(say: 'ציור רך', options: _chips));
    painter.finish();
    await _settle(tester);

    // 2. Second content choice: paints at the tap, alongside the turn.
    await tester.tap(find.text('עץ'));
    // The edit base is shrunk first (an image decode) — a few frames.
    await _settle(tester);
    expect(service.pending.length, 1, reason: 'the turn is still unanswered');
    expect(painter.prompts.length, 3, reason: 'speculative paint at the tap');
    expect(painter.prompts.last, contains('נוסף לסצנה: עץ'));
    expect(painter.bases.last, isNotNull, reason: 'an edit of the existing picture');
    expect(find.byType(ChosenPictos), findsOneWidget);
    // The answer confirms a scene: no second paint for the same choice.
    service.answer(const CompanionTurn(
        say: 'עץ', creationUpdate: 'עץ', sceneUpdate: 'כלב על דשא ליד עץ', options: _chips));
    await _settle(tester);
    expect(painter.prompts.length, 3);
    final second = painter.finish();
    await _settle(tester);
    expect(identical(_shownPicture(tester), second), isTrue);
    expect(find.byType(ChosenPictos), findsNothing);

    // 3. A paint that finishes BEFORE the answer is held, not shown.
    await tester.tap(find.text('אמא'));
    await _settle(tester);
    expect(painter.prompts.length, 4);
    painter.finish();
    await _settle(tester);
    expect(identical(_shownPicture(tester), second), isTrue,
        reason: 'held until the model agrees it is content');
    // The model asks a question instead: the held picture is dropped.
    service.answer(const CompanionTurn(
      say: 'איזו אמא?',
      needsConfirmation: true,
      confirm: ConfirmPrompt(question: 'איזו אמא?', options: ['אמא שלי', 'אמא של דן']),
    ));
    await _settle(tester);
    expect(identical(_shownPicture(tester), second), isTrue);
    expect(find.byType(ChosenPictos), findsNothing);
    expect(painter.prompts.length, 4, reason: 'no paint for a question');
  });

  testWidgets('a creation opened with "תמונה" paints even its first choice at the tap',
      (tester) async {
    final service = _Scripted();
    final painter = _Painter();
    ImagineService.override = painter.call;
    await _pumpScreen(tester, service);

    await tester.tap(find.text('תמונה'));
    await _settle(tester);
    expect(painter.prompts, isEmpty, reason: 'the type is not a thing to paint');
    service.answer(const CompanionTurn(say: 'על מה?', options: _chips));
    await _settle(tester);

    await tester.tap(find.text('כלב'));
    await _settle(tester);
    expect(service.pending.length, 1);
    expect(painter.prompts.length, 1, reason: 'first picture, at the tap');
    expect(painter.prompts.single, startsWith('כלב.'));
    expect(painter.bases.single, isNull);
    service.answer(const CompanionTurn(
        say: 'כלב', creationUpdate: 'כלב', sceneUpdate: 'כלב', options: _chips));
    await _settle(tester);
    expect(painter.prompts.length, 1, reason: 'no second paint for the same choice');
    final bytes = painter.finish();
    await _settle(tester);
    expect(identical(_shownPicture(tester), bytes), isTrue);
  });

  testWidgets('on a short landscape screen the whole style question is reachable',
      (tester) async {
    final service = _Scripted();
    final painter = _Painter();
    ImagineService.override = painter.call;
    // iPad 10.2" landscape in Safari: 1080 wide, ~670 left for the page.
    await _pumpScreen(tester, service, size: const Size(1080, 670));

    await tester.tap(find.text('כלב'));
    await tester.pump();
    service.answer(const CompanionTurn(
        say: 'כלב', creationUpdate: 'כלב', sceneUpdate: 'כלב', options: _chips));
    await _settle(tester);
    painter.finish();
    await _settle(tester);
    // All six styles are on screen (an overflow would have failed the test).
    for (final style in kSceneStyles) {
      expect(find.text('${style.emoji} ${style.name}'), findsOneWidget);
    }
    final last = find.text('${kSceneStyles.last.emoji} ${kSceneStyles.last.name}');
    await tester.ensureVisible(last);
    await tester.tap(last);
    await tester.pump();
    expect(service.inputs.last, '${kSceneStyles.last.emoji} ${kSceneStyles.last.name}');
  });
}
