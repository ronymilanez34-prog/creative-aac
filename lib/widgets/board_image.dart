import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// Shows a word's picture: an imported image file when there is one
/// (raster or SVG — symbol sets often ship as SVG), otherwise an emoji,
/// otherwise a neutral placeholder. One widget so every screen renders
/// imported vocabulary the same way.
class BoardImage extends StatelessWidget {
  const BoardImage({super.key, this.imagePath, this.emoji, this.size = 60});

  final String? imagePath;
  final String? emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path != null && File(path).existsSync()) {
      final image = path.toLowerCase().endsWith('.svg')
          ? SvgPicture.file(File(path), width: size, height: size, fit: BoxFit.contain)
          : Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _fallback(),
            );
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
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
