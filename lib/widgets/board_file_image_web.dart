import 'package:flutter/material.dart';

/// Web keeps imported board images as data URIs (see the web BoardStore).
/// SVG data URIs can't be decoded by [Image] — those fall back.
Widget? boardFileImage(String path, double size) {
  if (!path.startsWith('data:image/') || path.startsWith('data:image/svg')) {
    return null;
  }
  return Image.network(path, width: size, height: size, fit: BoxFit.cover);
}
