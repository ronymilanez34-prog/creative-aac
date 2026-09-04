/// Platform switch for the imported-board store: real files on device,
/// words-only on the web (no dart:io there). Both expose the same BoardStore
/// API — callers never know the difference.
export 'board_store_web.dart' if (dart.library.io) 'board_store_io.dart';
