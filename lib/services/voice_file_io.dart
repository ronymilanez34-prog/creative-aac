import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where the recorder should write, and how to collect the result — the
/// on-device side: a real temp file, read back and deleted after use.
Future<String> voiceRecordingPath() async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
}

Future<Uint8List?> readRecordedVoice(String pathOrUrl) async {
  try {
    final file = File(pathOrUrl);
    final bytes = await file.readAsBytes();
    // Best-effort cleanup — the recording now lives in preferences.
    try {
      await file.delete();
    } catch (_) {}
    return bytes;
  } catch (_) {
    return null;
  }
}
