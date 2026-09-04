import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders an imported board image from a file path (device builds).
/// Returns null when the file is missing so the caller shows its fallback.
Widget? boardFileImage(String path, double size) {
  final file = File(path);
  if (!file.existsSync()) return null;
  if (path.toLowerCase().endsWith('.svg')) {
    return SvgPicture.file(file, width: size, height: size, fit: BoxFit.contain);
  }
  return Image.file(
    file,
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}
