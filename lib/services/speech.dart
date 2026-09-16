import 'package:flutter_tts/flutter_tts.dart';

/// Read-aloud service (Hebrew). One utterance at a time — a new [speak]
/// cancels the previous one so rapid taps don't queue up.
class Speech {
  FlutterTts? _tts;
  bool _ready = false;

  /// TTS-safe text. Two field-found traps (16.9, "צ'יקו" came out as random
  /// letters):
  ///  • an ASCII apostrophe inside a Hebrew word reads as an abbreviation
  ///    mark — engines split the word and spell it out. A real Hebrew
  ///    geresh (U+05F3) keeps צ'יקו one spoken word.
  ///  • emoji and pictographs get read out ("smiling face…") or garbled —
  ///    they are for the eyes, so they are stripped before speaking.
  static String speakable(String text) {
    var t = text.replaceAllMapped(
      RegExp("(?<=[א-ת])['’`](?=[א-ת])"),
      (_) => '׳',
    );
    // Whitelist: Hebrew (incl. geresh/gershayim), Latin, digits, basic
    // punctuation. Everything else — emoji, symbols — becomes a space.
    t = t.replaceAll(
      RegExp("[^֐-״A-Za-z0-9 .,!?:;()\"'’\\-]"),
      ' ',
    );
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _ensureInit() async {
    if (_ready) return;
    final tts = FlutterTts();
    await tts.setLanguage('he-IL');
    await tts.setSpeechRate(0.45); // calm, clear pace
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);
    _tts = tts;
    _ready = true;
  }

  Future<void> speak(String text) async {
    final trimmed = speakable(text);
    if (trimmed.isEmpty) return;
    await _ensureInit();
    await _tts?.stop();
    await _tts?.setLanguage('he-IL');
    await _tts?.speak(trimmed);
  }

  Future<void> stop() async => _tts?.stop();

  void dispose() {
    _tts?.stop();
    _tts = null;
    _ready = false;
  }
}
