import 'dart:typed_data';
import 'dart:ui' as ui;

import 'board_reader_service.dart';

/// Prepares a picked file for the AI board reader: a picture is decoded and
/// re-encoded as PNG no wider/taller than [maxSide] (a phone photo is 4–12MB;
/// the words on a board read fine at 1600px and the upload stays small).
/// Anything the device can decode works — HEIC from an iPhone included on
/// the device. A PDF passes through as is.
///
/// Throws [BoardReaderException] with a Hebrew message when the file is
/// neither a picture nor a PDF.
Future<BoardPage> prepareBoardPage(Uint8List bytes, {int maxSide = 1600}) async {
  if (BoardReaderService.mediaTypeOf(bytes) == 'application/pdf') {
    if (bytes.length > 18 * 1000 * 1000) {
      throw const BoardReaderException('קובץ ה-PDF גדול מדי — נסו לשלוח פחות דפים');
    }
    return BoardPage(bytes, 'application/pdf');
  }
  try {
    final probe = await ui.instantiateImageCodec(bytes);
    final frame = await probe.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    final longest = w > h ? w : h;
    final scale = longest > maxSide ? maxSide / longest : 1.0;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: (w * scale).round(),
      targetHeight: (h * scale).round(),
    );
    final scaled = await codec.getNextFrame();
    final data = await scaled.image.toByteData(format: ui.ImageByteFormat.png);
    scaled.image.dispose();
    if (data == null) throw const BoardReaderException('לא הצלחנו לקרוא את התמונה');
    return BoardPage(data.buffer.asUint8List(), 'image/png');
  } on BoardReaderException {
    rethrow;
  } catch (_) {
    throw const BoardReaderException(
      'הקובץ הזה לא נפתח כתמונה. נסו צילום מסך (PNG/JPG) או PDF',
    );
  }
}
