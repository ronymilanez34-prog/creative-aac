import 'package:flutter/material.dart';

import '../theme.dart';
import 'board_file_image_web.dart'
    if (dart.library.io) 'board_file_image_io.dart';

/// Shows a word's picture: an imported image file when there is one
/// (raster or SVG — symbol sets often ship as SVG), otherwise an emoji,
/// otherwise a neutral placeholder. One widget so every screen renders
/// imported vocabulary the same way. On the web there are no image files,
/// so the fallback always shows.
class BoardImage extends StatelessWidget {
  const BoardImage({super.key, this.imagePath, this.emoji, this.size = 60});

  final String? imagePath;
  final String? emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path != null) {
      final image = boardFileImage(path, size);
      if (image != null) {
        return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
      }
    }
    return _fallback();
  }

  Widget _fallback() {
    if (emoji != null && emoji!.isNotEmpty) {
      return Text(emoji!, style: TextStyle(fontSize: size));
    }
    return Icon(Icons.chat_bubble_outline, size: size, color: AppColors.textSoft);
  }
}
