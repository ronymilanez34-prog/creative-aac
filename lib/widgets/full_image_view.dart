import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Full-screen look at a creation's picture, with pinch/scroll zoom —
/// "אני יוצר דברים אבל לא רואה הכל" (field feedback 22.9): details the
/// creator chose (a dolphin's sparkling eyes) are invisible in a 240px
/// card. Getting OUT must be easier than getting in (pilot 20.10: Shani
/// was stuck here): any single tap anywhere closes it — judged on the raw
/// pointer, so the zoom gestures can never swallow it — and a big
/// "חזרה" bar sits at the bottom. Only a pinch (two fingers) stays.
Future<void> showFullImage(BuildContext context, Uint8List image) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: _FullImage(image: image, onClose: () => Navigator.of(ctx).pop()),
    ),
  );
}

class _FullImage extends StatefulWidget {
  const _FullImage({required this.image, required this.onClose});

  final Uint8List image;
  final VoidCallback onClose;

  @override
  State<_FullImage> createState() => _FullImageState();
}

class _FullImageState extends State<_FullImage> {
  int _pointers = 0;
  bool _multi = false;
  Offset? _down;
  bool _closed = false;

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointers++;
        if (_pointers > 1) _multi = true;
        if (_pointers == 1) {
          _multi = false;
          _down = e.position;
        }
      },
      onPointerCancel: (_) => _pointers = 0,
      onPointerUp: (e) {
        _pointers = (_pointers - 1).clamp(0, 99);
        if (_pointers != 0 || _multi) return;
        final down = _down;
        _down = null;
        // A tap (generous slop for a shaky hand) closes; a long drag is
        // a pan around the zoomed picture and stays.
        if (down != null && (e.position - down).distance <= 48) _close();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 8,
              child: Center(
                child: Image.memory(
                  widget.image,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
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
                iconSize: 40,
                padding: const EdgeInsets.all(14),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _close,
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: SafeArea(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: _close,
                  child: const SizedBox(
                    height: 76,
                    child: Center(
                      child: Text(
                        '⬅️ חזרה',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E3330),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
