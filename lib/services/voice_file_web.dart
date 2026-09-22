import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The web side: the recorder ignores the path (an empty one is fine) and
/// `stop()` returns a blob: URL — the browser fetches its own blob.
Future<String> voiceRecordingPath() async => '';

Future<Uint8List?> readRecordedVoice(String pathOrUrl) async {
  try {
    return await http.readBytes(Uri.parse(pathOrUrl));
  } catch (_) {
    return null;
  }
}
