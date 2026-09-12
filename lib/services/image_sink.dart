import 'dart:typed_data';

/// Where the importer puts button images. Injected so the parsing code has
/// no dart:io dependency and the web build compiles: on-device imports write
/// real files; on the web images are skipped (words-only import).
abstract class ImageSink {
  /// Stores [data] under [name]; returns the stored file name, or null when
  /// this sink does not keep images.
  String? write(String name, Uint8List data);
}

class NoopImageSink implements ImageSink {
  const NoopImageSink();

  @override
  String? write(String name, Uint8List data) => null;
}

/// Keeps images in memory (name → bytes) up to a byte budget — the web
/// board store persists them as data URIs in browser storage afterwards.
/// Past the budget, words still import, just without their picture.
class MemoryImageSink implements ImageSink {
  MemoryImageSink({this.budgetBytes = 3 * 1000 * 1000});

  final int budgetBytes;
  final Map<String, Uint8List> images = {};
  int _used = 0;

  @override
  String? write(String name, Uint8List data) {
    if (_used + data.length > budgetBytes) return null;
    _used += data.length;
    images[name] = data;
    return name;
  }
}
