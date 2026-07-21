import 'package:flutter_tts/flutter_tts.dart';

/// Read-aloud service (Hebrew). One utterance at a time — a new [speak]
/// cancels the previous one so rapid taps don't queue up.
class Speech {
  FlutterTts? _tts;
  bool _ready = false;

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
    final trimmed = text.trim();
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
