import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'image_sink.dart';
import 'obz_importer.dart';
import 'sqlite_reader.dart';
import 'touchchat_importer.dart';

/// The one import door: whatever board file the staff picks, look at what
/// it actually IS (its bytes, not its name — iOS pickers rename and strip
/// extensions) and hand it to the right translator. Every translator
/// returns the same thing: the friend's words, with their spoken text and
/// picture when there is one.
///
/// Known today:
///  • Open Board (.obz zip / .obf JSON) — the open standard.
///  • TouchChat (.ce zip / .c4v SQLite) — the village's app.
/// Next, by plan (HANDOVER): a picture/PDF of a board read by the AI, as
/// the net for every format without a translator yet.
class BoardImporter {
  Future<ObzImportResult> import({
    required Uint8List bytes,
    required ImageSink images,
  }) async {
    switch (detect(bytes)) {
      case BoardFormat.touchChatZip:
        return TouchChatImporter()
            .import(bytes: bytes, images: images, archive: ZipDecoder().decodeBytes(bytes));
      case BoardFormat.touchChatDb:
        return TouchChatImporter().import(bytes: bytes, images: images);
      case BoardFormat.openBoard:
        return ObzImporter().import(bytes: bytes, images: images);
      case BoardFormat.pdf:
      case BoardFormat.image:
        throw const ObzFormatException(
          'זו תמונה או PDF של לוח — קריאת לוח מתמונה עוד לא קיימת.\n'
          'בינתיים: ייצאו את הלוח מאפליקציית התקשורת (TouchChat או ‎.obz)',
        );
      case BoardFormat.unknown:
        throw const ObzFormatException(
          'לא זיהינו את סוג הקובץ.\n'
          'אפשר לייבא לוח מ-TouchChat (‎.ce) או לוח פתוח (‎.obz / ‎.obf)',
        );
    }
  }

  /// What [bytes] are. Public for tests.
  static BoardFormat detect(Uint8List bytes) {
    if (bytes.length < 4) return BoardFormat.unknown;
    final b = bytes;
    if (b[0] == 0x50 && b[1] == 0x4B) {
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        if (TouchChatImporter.looks(bytes, archive: archive)) {
          return BoardFormat.touchChatZip;
        }
      } catch (_) {
        // A broken zip — let the Open Board path give its own message.
      }
      return BoardFormat.openBoard;
    }
    if (SqliteReader.isSqlite(bytes)) {
      return TouchChatImporter.looks(bytes)
          ? BoardFormat.touchChatDb
          : BoardFormat.unknown;
    }
    if (b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) {
      return BoardFormat.pdf; // %PDF
    }
    if ((b[0] == 0x89 && b[1] == 0x50) ||
        (b[0] == 0xFF && b[1] == 0xD8) ||
        (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) ||
        _isHeif(b) ||
        (b.length > 12 && b[0] == 0x52 && b[8] == 0x57 && b[9] == 0x45)) {
      return BoardFormat.image; // PNG, JPEG, GIF, HEIC (iPhone photos), WEBP
    }
    // JSON (.obf) — first non-space character is '{' (UTF-8 BOM allowed).
    var i = 0;
    if (b.length > 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) i = 3;
    while (i < b.length && (b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09)) {
      i++;
    }
    if (i < b.length && b[i] == 0x7B) return BoardFormat.openBoard;
    return BoardFormat.unknown;
  }
}

/// iPhone photos: an ISO box "ftyp" with a HEIF/AVIF brand.
bool _isHeif(Uint8List b) {
  if (b.length < 12 || String.fromCharCodes(b.sublist(4, 8)) != 'ftyp') return false;
  const brands = {'heic', 'heix', 'hevc', 'heim', 'heis', 'mif1', 'msf1', 'avif'};
  return brands.contains(String.fromCharCodes(b.sublist(8, 12)));
}

enum BoardFormat { openBoard, touchChatZip, touchChatDb, pdf, image, unknown }
