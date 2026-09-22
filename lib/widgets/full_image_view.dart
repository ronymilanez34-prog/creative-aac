import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Full-screen look at a creation's picture, with pinch/scroll zoom —
/// "אני יוצר דברים אבל לא רואה הכל" (field feedback 22.9): details the
/// creator chose (a dolphin's sparkling eyes) are invisible in a 240px
/// card. Tap anywhere outside the picture, or the big ✕, to come back.
Future<void> showFullImage(BuildContext context, Uint8List image) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: InteractiveViewer(
                maxScale: 8,
                child: Center(
                  child: Image.memory(
                    image,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 28,
            start: 20,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'סגירה',
                iconSize: 34,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
