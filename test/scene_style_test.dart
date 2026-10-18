import 'package:creative_aac/models/companion.dart';
import 'package:creative_aac/services/scene_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a style is recognised by its bare name and its emoji-prefixed form',
      () {
    expect(styleFromLabel('ציור רך'), kSceneStyles.first);
    expect(styleFromLabel('🎨 ציור רך'), kSceneStyles.first);
    expect(styleFromLabel(' 🌊 צבעי מים '), isNotNull);
    expect(styleFromLabel('כלב'), isNull);
    expect(styleFromLabel('סגנון אחר'), isNull);
  });

  test('the style question offers every style, each answer maps back', () {
    expect(kStyleQuestionOptions.length, kSceneStyles.length);
    for (final o in kStyleQuestionOptions) {
      expect(styleFromLabel(o), isNotNull);
    }
  });

  test('withConfirm keeps the turn and adds the question', () {
    const turn = CompanionTurn(
      say: 'הנה כלב',
      sceneUpdate: 'כלב על רקע פשוט',
      options: [ChipOption(emoji: '🌳', label: 'בפארק')],
    );
    final asked = turn.withConfirm(const ConfirmPrompt(
      question: kStyleQuestion,
      options: ['🎨 ציור רך'],
    ));
    expect(asked.needsConfirmation, isTrue);
    expect(asked.confirm?.question, kStyleQuestion);
    expect(asked.say, turn.say);
    expect(asked.sceneUpdate, turn.sceneUpdate);
    expect(asked.options, turn.options);
  });
}
