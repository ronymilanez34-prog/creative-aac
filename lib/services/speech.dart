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

  /// Once per app run: a near-silent utterance fired from INSIDE a user
  /// gesture. iOS (Safari, and web views) refuses speech that did not
  /// start from a touch — without this, every later speak() that follows
  /// an await (a model turn, a timer) is silently dropped.
  static bool _warmedUp = false;

  Future<void> warmUp() async {
    if (_warmedUp) return;
    _warmedUp = true;
    try {
      await _ensureInit();
      await _tts?.speak(' ');
      await _tts?.stop();
    } catch (_) {
      // Warm-up is best-effort; real speaks carry their own handling.
    }
  }

  /// Hebrew goes by two BCP-47 codes in the wild: 'he' and the legacy
  /// 'iw' (older Android engines register only the latter). Try both —
  /// a failed setLanguage is how "the voice doesn't work on the phone"
  /// happens with no error anywhere.
  Future<void> _setHebrew(FlutterTts tts) async {
    try {
      final r = await tts.setLanguage('he-IL');
      if (r == 0 || r == false) await tts.setLanguage('iw-IL');
    } catch (_) {
      try {
        await tts.setLanguage('iw-IL');
      } catch (_) {}
    }
  }

  /// Whether the device has any Hebrew voice. null = the engine didn't
  /// say (common on web) — treat as "probably fine", never as failure.
  Future<bool?> hasHebrewVoice() async {
    try {
      await _ensureInit();
      final voices = await _tts?.getVoices;
      if (voices is! List || voices.isEmpty) return null;
      for (final v in voices) {
        final s = (v is Map ? '${v['locale']} ${v['name']}' : v.toString())
            .toLowerCase();
        if (s.contains('he-') || s.contains('he_') ||
            s.contains('iw-') || s.contains('iw_') ||
            s.contains('hebrew')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureInit() async {
    if (_ready) return;
    final tts = FlutterTts();
    await _setHebrew(tts);
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
    final tts = _tts;
    if (tts != null) await _setHebrew(tts);
    await _tts?.speak(trimmed);
  }

  /// On-screen diagnosis for remote debugging ("the voice doesn't work on
  /// the phone" must never be a guessing game): initializes, lists what
  /// the engine reports, and fires a REAL spoken sentence from inside the
  /// button's own gesture — the strongest test iOS allows. The returned
  /// text is shown to the person; a screenshot of it tells us everything.
  Future<String> diagnose() async {
    final b = StringBuffer();
    try {
      await _ensureInit();
      b.writeln('אתחול המנוע: תקין');
    } catch (e) {
      b.writeln('אתחול המנוע נכשל: $e');
      return b.toString();
    }
    try {
      final voices = await _tts?.getVoices;
      if (voices is List && voices.isNotEmpty) {
        b.writeln('קולות במכשיר: ${voices.length}');
        final he = [
          for (final v in voices)
            if (RegExp(r'he[-_]|iw[-_]|hebrew', caseSensitive: false)
                .hasMatch(v.toString()))
              v,
        ];
        b.writeln('קולות עברית: ${he.length}');
        if (he.isNotEmpty) b.writeln('למשל: ${he.first}');
      } else {
        b.writeln('המנוע לא מדווח רשימת קולות (נפוץ בדפדפן)');
      }
    } catch (e) {
      b.writeln('קריאת קולות נכשלה: $e');
    }
    try {
      final r = await _tts?.speak('שלום! זו בדיקת קול.');
      b.writeln('פקודת דיבור נשלחה (החזירה: $r)');
      b.writeln('אם לא נשמע כלום עכשיו — בדקו מתג השתקה ווליום.');
    } catch (e) {
      b.writeln('פקודת הדיבור נכשלה: $e');
    }
    return b.toString();
  }

  Future<void> stop() async => _tts?.stop();

  void dispose() {
    _tts?.stop();
    _tts = null;
    _ready = false;
  }
}
