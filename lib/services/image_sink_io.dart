import 'dart:io';
import 'dart:typed_data';

import 'image_sink.dart';

/// Writes button images into a directory (mobile/desktop).
class DirectoryImageSink implements ImageSink {
  DirectoryImageSink(this.dir);

  final Directory dir;

  @override
  String? write(String name, Uint8List data) {
    File('${dir.path}/$name').writeAsBytesSync(data);
    return name;
  }
}
