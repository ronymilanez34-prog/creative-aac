import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

import 'voice_file.dart';

/// Recording and playing back the creator's own voice — the full answer to
/// the 10.9 field note: a name or an invented word must sound the way its
/// owner says it, not the way TTS guesses. Clips are seconds long, stored
/// as audio data URIs inside the lexicon JSON (SharedPreferences), so the
/// full backup carries the voice with the words.
///
/// Everything here is best-effort and silent on failure: a microphone that
/// refuses is a missing recording, never a broken screen — TTS remains the
/// floor that always works.

/// Longest clip we keep — a word or a short name, not a story.
const int kMaxVoiceSeconds = 10;

/// Guard for browser storage (the web pilot keeps everything in
/// localStorage next to the board images): ~10s of 16kHz mono WAV fits.
const int _kMaxVoiceBytes = 700 * 1024;

/// Sniffs the audio container of a finished recording. Different platforms
/// hand back different containers for the "same" recording (Chrome:
/// webm/opus, Safari: mp4, device: m4a, the universal fallback: wav) — the
/// bytes themselves say which one arrived.
String sniffAudioMime(List<int> bytes) {
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 && // RIFF....WAVE
      bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x41 &&
      bytes[10] == 0x56 && bytes[11] == 0x45) {
    return 'audio/wav';
  }
  if (bytes.length >= 8 &&
      bytes[4] == 0x66 && bytes[5] == 0x74 && // ....ftyp → MP4 / M4A
      bytes[6] == 0x79 && bytes[7] == 0x70) {
    return 'audio/mp4';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x1A && bytes[1] == 0x45 && // EBML → WebM/Matroska
      bytes[2] == 0xDF && bytes[3] == 0xA3) {
    return 'audio/webm';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x4F && bytes[1] == 0x67 && // OggS
      bytes[2] == 0x67 && bytes[3] == 0x53) {
    return 'audio/ogg';
  }
  if (bytes.length >= 2 &&
      bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0) { // ADTS AAC
    return 'audio/aac';
  }
  return 'audio/webm';
}

String audioDataUri(Uint8List bytes) =>
    'data:${sniffAudioMime(bytes)};base64,${base64Encode(bytes)}';

/// The bytes inside an audio data URI, or null when it isn't one — a
/// corrupt stored clip must never take a screen down.
Uint8List? audioDataUriBytes(String dataUri) {
  final comma = dataUri.indexOf(',');
  if (!dataUri.startsWith('data:audio/') || comma < 0) return null;
  try {
    return base64Decode(dataUri.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

class VoiceNotes {
  VoiceNotes._();

  static final AudioRecorder _recorder = AudioRecorder();
  static AudioPlayer? _player;
  static bool _recording = false;

  static bool get isRecording => _recording;

  /// The first supported encoder wins: compressed where the platform can
  /// (device AAC, Chrome opus/webm), and WAV as the floor that records
  /// everywhere `record` runs — including Safari, the pilot's browser.
  static Future<AudioEncoder> _pickEncoder() async {
    for (final e in [AudioEncoder.aacLc, AudioEncoder.opus]) {
      try {
        if (await _recorder.isEncoderSupported(e)) return e;
      } catch (_) {}
    }
    return AudioEncoder.wav;
  }

  /// Starts recording (asking the browser/OS for the microphone on the
  /// way). false = no permission or no recorder — the caller shows a calm
  /// "it didn't work" instead of a spinner that never ends.
  static Future<bool> start() async {
    if (_recording) return true;
    try {
      if (!await _recorder.hasPermission()) return false;
      await stopPlayback();
      final encoder = await _pickEncoder();
      await _recorder.start(
        RecordConfig(
          encoder: encoder,
          bitRate: 32000,
          sampleRate: 16000, // speech-sized: keeps WAV clips small enough
          numChannels: 1,
        ),
        path: await voiceRecordingPath(),
      );
      _recording = true;
      return true;
    } catch (_) {
      _recording = false;
      return false;
    }
  }

  /// Stops and returns the clip as a data URI, or null when nothing usable
  /// was captured (denied, empty, or too large to store safely).
  static Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    try {
      final location = await _recorder.stop();
      if (location == null || location.isEmpty) return null;
      final bytes = await readRecordedVoice(location);
      if (bytes == null || bytes.length < 200) return null;
      if (bytes.length > _kMaxVoiceBytes) return null;
      return audioDataUri(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Stops and discards — closing the sheet mid-recording leaves nothing.
  static Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  /// Plays a stored clip. One voice at a time — a new play stops the last.
  static Future<void> play(String dataUri) async {
    if (dataUri.trim().isEmpty) return;
    try {
      final p = _player ??= AudioPlayer();
      await p.stop();
      if (kIsWeb) {
        // The browser's audio element takes the data URI as-is.
        await p.play(UrlSource(dataUri));
      } else {
        final bytes = audioDataUriBytes(dataUri);
        if (bytes == null) return;
        await p.play(BytesSource(bytes));
      }
    } catch (_) {
      // A clip that won't play is a silent tap, never an error screen.
    }
  }

  static Future<void> stopPlayback() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
