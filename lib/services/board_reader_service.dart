import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

/// One word the AI read off a picture of a board. [sure] is false when the
/// text was hard to read or the word was guessed from a symbol — the review
/// screen marks those so the staff look twice.
class ReadWord {
  const ReadWord(this.label, {this.sure = true});
  final String label;
  final bool sure;
}

/// A page to read: a picture (already shrunk) or a PDF.
class BoardPage {
  const BoardPage(this.bytes, this.mediaType);
  final Uint8List bytes;
  final String mediaType;
}

/// The import door's AI net: pictures/PDF of a board → the words on it,
/// via the backend's `readBoardHttp` (functions/board_reader.js). Nothing is
/// saved here — the staff review the list first.
class BoardReaderService {
  /// Same function host as the companion.
  static String get endpoint =>
      kCompanionEndpoint.replaceFirst('companionTurnHttp', 'readBoardHttp');

  static bool get available => kCompanionEndpoint.isNotEmpty;

  Future<List<ReadWord>> read(List<BoardPage> pages) async {
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'content-type': 'application/json',
            if (kCompanionAppKey.isNotEmpty) 'x-app-key': kCompanionAppKey,
          },
          body: jsonEncode({
            'pages': [
              for (final p in pages)
                {'mediaType': p.mediaType, 'dataB64': base64Encode(p.bytes)},
            ],
          }),
        )
        .timeout(const Duration(seconds: 120));
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    if (res.statusCode != 200) {
      final msg = body is Map && body['error'] != null
          ? body['error'].toString()
          : 'שגיאה (${res.statusCode})';
      throw BoardReaderException(msg);
    }
    final list = body is Map ? body['words'] : null;
    if (list is! List) throw const BoardReaderException('תשובה לא צפויה מהשרת');
    return [
      for (final w in list.whereType<Map>())
        if ((w['label'] ?? '').toString().trim().isNotEmpty)
          ReadWord(w['label'].toString().trim(), sure: w['sure'] != false),
    ];
  }

  /// The media type of a picked file, by content. Null = not a picture/PDF.
  static String? mediaTypeOf(Uint8List b) {
    if (b.length < 4) return null;
    if (b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) return 'application/pdf';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) {
      return 'image/webp'; // RIFF....WEBP
    }
    return null;
  }
}

class BoardReaderException implements Exception {
  const BoardReaderException(this.message);
  final String message;
  @override
  String toString() => message;
}
