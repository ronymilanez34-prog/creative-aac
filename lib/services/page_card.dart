import 'dart:typed_data';
import 'dart:ui' as ui;

import 'hebrew_text.dart';

/// A page of the story as ONE picture — the painted scene on top, the
/// creator's own words big beneath it, the companion's telling small
/// under those. Built for sharing: WhatsApp (and friends) drop the text
/// when files are attached, so the words ride inside the image, and what
/// arrives looks like a page of a book (field 18.10).
///
/// Returns PNG bytes, or null when nothing could be drawn.
Future<Uint8List?> renderPageCard({
  Uint8List? picture,
  required String words,
  String? told,
  String storyLabel = 'פז מספר',
  String? title,
  int? pageNumber,
  int? pageCount,
}) async {
  const width = 1080.0;
  const margin = 56.0;
  const paper = ui.Color(0xFFFBF7F0);
  const ink = ui.Color(0xFF2B2F2C);
  const soft = ui.Color(0xFF6E756F);
  const accent = ui.Color(0xFF6C8EBF);

  ui.Image? image;
  if (picture != null && picture.isNotEmpty) {
    try {
      final codec = await ui.instantiateImageCodec(picture);
      image = (await codec.getNextFrame()).image;
    } catch (_) {
      image = null;
    }
  }

  ui.Paragraph paragraph(String text, double size, ui.Color color,
      {ui.FontWeight weight = ui.FontWeight.w400, double height = 1.45}) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: ui.TextDirection.rtl,
      textAlign: ui.TextAlign.center,
      fontSize: size,
      height: height,
      fontWeight: weight,
    ))
      ..pushStyle(ui.TextStyle(color: color, fontSize: size, fontWeight: weight))
      ..addText(text);
    final p = builder.build()
      ..layout(const ui.ParagraphConstraints(width: width - 2 * margin));
    return p;
  }

  final wordsText = stripNikud(words.trim());
  final toldText = stripNikud((told ?? '').trim());
  final titleText = (title ?? '').trim();
  final hasWords = wordsText.isNotEmpty;
  final hasTold = toldText.isNotEmpty;
  if (image == null && !hasWords && !hasTold) return null;

  final titleP = titleText.isEmpty
      ? null
      : paragraph(titleText, 30, soft, weight: ui.FontWeight.w600);
  final wordsP =
      hasWords ? paragraph(wordsText, 46, ink, weight: ui.FontWeight.w700) : null;
  final labelP = hasTold
      ? paragraph(storyLabel, 26, accent, weight: ui.FontWeight.w700)
      : null;
  final toldP = hasTold ? paragraph(toldText, 34, soft) : null;
  final footP = pageNumber == null
      ? null
      : paragraph(
          pageCount == null ? 'דף $pageNumber' : 'דף $pageNumber מתוך $pageCount',
          24,
          soft);

  // Picture scaled to the page width, never upscaled past 2x.
  double imageH = 0;
  double imageW = 0;
  if (image != null) {
    final scale = ((width - 2 * margin) / image.width).clamp(0.0, 2.0);
    imageW = image.width * scale;
    imageH = image.height * scale;
  }

  var height = margin;
  if (titleP != null) height += titleP.height + 20;
  if (image != null) height += imageH + 32;
  if (wordsP != null) height += wordsP.height + 20;
  if (labelP != null) height += labelP.height + 6;
  if (toldP != null) height += toldP.height + 16;
  if (footP != null) height += footP.height;
  height += margin;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = paper);

  var y = margin;
  if (titleP != null) {
    canvas.drawParagraph(titleP, ui.Offset(margin, y));
    y += titleP.height + 20;
  }
  if (image != null) {
    final x = (width - imageW) / 2;
    final dst = ui.Rect.fromLTWH(x, y, imageW, imageH);
    final rrect = ui.RRect.fromRectAndRadius(dst, const ui.Radius.circular(24));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
    y += imageH + 32;
  }
  if (wordsP != null) {
    canvas.drawParagraph(wordsP, ui.Offset(margin, y));
    y += wordsP.height + 20;
  }
  if (labelP != null) {
    canvas.drawParagraph(labelP, ui.Offset(margin, y));
    y += labelP.height + 6;
  }
  if (toldP != null) {
    canvas.drawParagraph(toldP, ui.Offset(margin, y));
    y += toldP.height + 16;
  }
  if (footP != null) {
    canvas.drawParagraph(footP, ui.Offset(margin, y));
  }

  final pic = recorder.endRecording();
  final out = await pic.toImage(width.round(), height.round());
  image?.dispose();
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  return data?.buffer.asUint8List();
}
