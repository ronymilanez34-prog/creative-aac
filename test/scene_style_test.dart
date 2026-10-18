import 'package:creative_aac/models/companion.dart';
import 'package:creative_aac/models/profile.dart';
import 'package:creative_aac/models/story.dart';
import 'package:creative_aac/services/creation_context.dart';
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

  test('a question-like label is never content', () {
    expect(isQuestionLike('איזה צבע הדג'), isTrue);
    expect(isQuestionLike('מה עכשיו?'), isTrue);
    expect(isQuestionLike('איפה הכלב'), isTrue);
    expect(isQuestionLike('הדג מחייך'), isFalse);
    expect(isQuestionLike('גלים גבוהים'), isFalse);
    expect(isQuestionLike('סגול'), isFalse);
  });

  test('page_story is parsed and survives withConfirm', () {
    final t = CompanionTurn.fromJson(const {
      'say': 'הנה',
      'page_story': 'על ראש ההר עומד עץ גבוה.',
    });
    expect(t.pageStory, 'על ראש ההר עומד עץ גבוה.');
    expect(t.withConfirm(const ConfirmPrompt(question: 'q', options: ['a']))
        .pageStory, t.pageStory);
    expect(CompanionTurn.fromJson(const {'say': 'x'}).pageStory, isNull);
  });

  test('a story page keeps both layers across save and load', () {
    const page = StoryPage(
      text: 'עץ · ציפור',
      told: 'על ראש ההר עומד עץ, וציפור מגיעה אליו.',
      emoji: '✨',
    );
    final back = StoryPage.fromJson(page.toJson());
    expect(back.text, page.text);
    expect(back.told, page.told);
    expect(back.withoutImage().told, page.told);
    // Pages from before the layer existed still load.
    expect(StoryPage.fromJson(const {'text': 'a', 'emoji': 'b'}).told, isNull);
  });

  test('scene_change is parsed, defaults to false, survives withConfirm', () {
    expect(CompanionTurn.fromJson(const {'say': 'x', 'scene_change': true})
        .sceneChange, isTrue);
    expect(CompanionTurn.fromJson(const {'say': 'x'}).sceneChange, isFalse);
    const t = CompanionTurn(say: 'x', sceneChange: true);
    expect(t.withConfirm(const ConfirmPrompt(question: 'q', options: ['a']))
        .sceneChange, isTrue);
    expect(styleFromLabel(kNewPageYes), isNull);
  });

  test('the AI has a name: the default, or the creator\'s own', () {
    expect(UserProfile().effectiveCompanionName, kDefaultCompanionName);
    expect(UserProfile(companionName: ' טוטו ').effectiveCompanionName,
        'טוטו');
    final back = UserProfile.fromJson(
        UserProfile(name: 'דני', companionName: 'לולי').toJson());
    expect(back.companionName, 'לולי');
    expect(UserProfile.fromJson(const {'name': 'דני'}).companionName, '');
  });
}
