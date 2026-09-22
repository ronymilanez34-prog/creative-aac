import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:creative_aac/models/lexicon.dart';
import 'package:creative_aac/services/voice_notes.dart';
import 'package:creative_aac/services/voice_registry.dart';

void main() {
  group('LexiconWord voice field', () {
    test('roundtrips through JSON', () {
      const w = LexiconWord(
        word: 'בָּמְבִּי',
        emoji: '🦌',
        meaning: 'חבר רך',
        voice: 'data:audio/webm;base64,AAAA',
        createdAtMs: 5,
      );
      final back = LexiconWord.fromJson(w.toJson());
      expect(back.voice, w.voice);
      expect(back.hasVoice, isTrue);
    });

    test('missing voice reads as empty, and empty is omitted from JSON',
        () {
      final w = LexiconWord.fromJson(
          {'word': 'זומזום', 'emoji': '🐝', 'meaning': ''});
      expect(w.voice, '');
      expect(w.hasVoice, isFalse);
      expect(w.toJson().containsKey('voice'), isFalse);
    });

    test('a stored lexicon with voices survives decode', () {
      const lex = Lexicon(name: 'רוניקית', words: [
        const LexiconWord(
            word: 'זומזום',
            emoji: '🐝',
            meaning: 'שמחה',
            voice: 'data:audio/wav;base64,AAAA'),
      ]);
      final back = Lexicon.decode(lex.encode());
      expect(back.words.single.voice, 'data:audio/wav;base64,AAAA');
    });
  });

  group('sniffAudioMime', () {
    Uint8List rig(List<int> head) =>
        Uint8List.fromList([...head, ...List.filled(20, 0)]);

    test('recognizes WAV', () {
      final b = rig([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      expect(sniffAudioMime(b), 'audio/wav');
    });

    test('recognizes MP4/M4A', () {
      final b = rig([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]);
      expect(sniffAudioMime(b), 'audio/mp4');
    });

    test('recognizes WebM', () {
      expect(sniffAudioMime(rig([0x1A, 0x45, 0xDF, 0xA3])), 'audio/webm');
    });

    test('recognizes Ogg', () {
      expect(sniffAudioMime(rig([0x4F, 0x67, 0x67, 0x53])), 'audio/ogg');
    });

    test('recognizes ADTS AAC', () {
      expect(sniffAudioMime(rig([0xFF, 0xF1])), 'audio/aac');
    });
  });

  group('audio data URIs', () {
    test('roundtrip bytes → data URI → bytes', () {
      final bytes = Uint8List.fromList(
          [0x1A, 0x45, 0xDF, 0xA3, 1, 2, 3, 4, 5, 6, 7, 8]);
      final uri = audioDataUri(bytes);
      expect(uri, startsWith('data:audio/webm;base64,'));
      expect(audioDataUriBytes(uri), bytes);
    });

    test('rejects non-audio and corrupt input without throwing', () {
      expect(audioDataUriBytes('data:image/png;base64,AAAA'), isNull);
      expect(audioDataUriBytes('data:audio/webm;base64,@@@'), isNull);
      expect(audioDataUriBytes('not a uri'), isNull);
    });
  });

  group('VoiceRegistry', () {
    const clip = 'data:audio/webm;base64,AAAA';

    setUp(() {
      VoiceRegistry.update(const Lexicon(words: [
        LexiconWord(word: 'זומזום', emoji: '🐝', meaning: '', voice: clip),
        LexiconWord(word: 'בלי-קול', emoji: '🌙', meaning: ''),
      ]));
    });

    tearDown(() => VoiceRegistry.update(const Lexicon()));

    test('the word alone finds its recording', () {
      expect(VoiceRegistry.lookup('זומזום'), clip);
      expect(VoiceRegistry.lookup('  זומזום  '), clip);
    });

    test('UI wrapping around the word still matches', () {
      expect(VoiceRegistry.lookup('«זומזום»'), clip);
      expect(VoiceRegistry.lookup('זומזום!'), clip);
    });

    test('a sentence containing the word is NOT the word', () {
      expect(VoiceRegistry.lookup('איזה זומזום נחמד'), isNull);
    });

    test('a word without a recording falls through to TTS', () {
      expect(VoiceRegistry.lookup('בלי-קול'), isNull);
    });
  });
}
