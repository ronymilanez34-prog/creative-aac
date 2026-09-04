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
