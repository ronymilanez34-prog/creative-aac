import 'package:creative_aac/services/scene_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scenePaintPrompt', () {
    test('every variant carries the scene and the only-what-was-chosen rule',
        () {
      for (final p in [
        scenePaintPrompt('כלב', hasBase: false, freshPage: false),
        scenePaintPrompt('כלב', hasBase: true, freshPage: false),
        scenePaintPrompt('כלב', hasBase: true, freshPage: true),
      ]) {
        expect(p, contains('כלב'));
        expect(p, contains(kOnlyWhatWasChosen));
        expect(p, contains('רקע פשוט'));
        expect(p, contains('בלי שום כתב בתמונה'));
      }
    });

    test('no style chosen → the soft-illustration default, never a photo',
        () {
      final p = scenePaintPrompt('כלב', hasBase: false, freshPage: false);
      expect(p, contains('סגנון: $kDefaultSceneStylePrompt.'));
      expect(kDefaultSceneStylePrompt, contains('לא צילום'));
    });

    test('a chosen style replaces the default', () {
      final p = scenePaintPrompt('כלב',
          hasBase: false, freshPage: false, stylePrompt: 'קומיקס');
      expect(p, contains('סגנון: קומיקס.'));
      expect(p, isNot(contains(kDefaultSceneStylePrompt)));
    });

    test('a chosen style rides in every variant', () {
      final p = scenePaintPrompt('כלב',
          hasBase: true, freshPage: false, stylePrompt: 'צבעי מים');
      expect(p, contains('סגנון: צבעי מים.'));
      expect(p, startsWith('ערוך את התמונה'));
    });

    test('a fresh page keeps the characters, a first picture edits nothing',
        () {
      expect(scenePaintPrompt('כלב', hasBase: true, freshPage: true),
          contains('אותן דמויות'));
      expect(scenePaintPrompt('כלב', hasBase: false, freshPage: false),
          isNot(contains('ערוך')));
    });
  });
}
