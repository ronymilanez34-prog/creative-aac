/// Platform switch for reading a finished recording off the recorder:
/// on device the `record` plugin writes a real file (dart:io reads it);
/// on the web it hands back a blob URL (fetched over XHR). Same API both
/// ways — voice_notes.dart never knows the difference.
library;

export 'voice_file_web.dart' if (dart.library.io) 'voice_file_io.dart';
