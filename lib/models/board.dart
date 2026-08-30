/// The user's personal vocabulary, imported from their existing AAC app.
///
/// A [BoardWord] is one button from the user's own communication board: the
/// label they already know, the exact image they already recognize, and the
/// text to speak. Familiarity is the whole point — see docs/VISION.md.

class BoardWord {
  const BoardWord({
    required this.id,
    required this.label,
    this.speak,
    this.imageFile,
    this.imagePath,
  });

  final String id;

  /// The text on the button — the word as the user knows it.
  final String label;

  /// What the button says out loud, when different from [label].
  final String? speak;

  /// File name of the button's image inside the app's board-images folder
  /// (relative — the folder's absolute location can change between app
  /// launches on iOS, so it is resolved at load time).
  final String? imageFile;

  /// Absolute path to the image, resolved by [BoardStore] when loading.
  /// Null when the word has no image.
  final String? imagePath;

  String get spokenText => (speak != null && speak!.trim().isNotEmpty) ? speak! : label;

  BoardWord withImagePath(String? path) => BoardWord(
        id: id,
        label: label,
        speak: speak,
        imageFile: imageFile,
        imagePath: path,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (speak != null) 'speak': speak,
        if (imageFile != null) 'imageFile': imageFile,
      };

  factory BoardWord.fromJson(Map<String, dynamic> j) => BoardWord(
        id: j['id'] as String,
        label: j['label'] as String,
        speak: j['speak'] as String?,
        imageFile: j['imageFile'] as String?,
      );
}
