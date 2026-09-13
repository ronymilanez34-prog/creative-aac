import 'dart:typed_data';
import 'dart:ui' as ui;

/// Shrinks a generated picture before it is stored with a story.
///
/// Browser storage is the pilot's disk and it is small; a full-size PNG from
/// the generator (~1-2MB) would let two or three pictures crowd out
/// everything else. Downscaling to [maxWidth] keeps a picture at "show it
/// on a phone" quality for a fraction of the bytes. Any failure returns the
/// original bytes — shrinking is an optimization, never a gate.
Future<Uint8List> shrinkForStorage(Uint8List bytes,
    {int maxWidth = 640}) async {
  try {
    // First decode reads the true size; only downscale, never upscale.
    final probe = await ui.instantiateImageCodec(bytes);
    final frame = await probe.getFrame();
    final width = frame.image.width;
    frame.image.dispose();
    if (width <= maxWidth) return bytes;

    final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
    final scaled = await codec.getFrame();
    final data =
        await scaled.image.toByteData(format: ui.ImageByteFormat.png);
    scaled.image.dispose();
    if (data == null) return bytes;
    final out = data.buffer.asUint8List();
    return out.length < bytes.length ? out : bytes;
  } catch (_) {
    return bytes;
  }
}
