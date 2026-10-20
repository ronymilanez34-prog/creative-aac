import 'package:flutter/material.dart';

/// A tap that forgives a shaky finger.
///
/// Flutter cancels a tap once the finger drifts ~18px; a hand with motor
/// difficulty drifts more than that while pressing, and the press is
/// silently lost ("הכפתורים לא נלחצו כמו שצריך", pilot 20.10). This fires
/// on release when ONE finger went down and came up inside the widget,
/// having moved less than [slop] — generous enough for a wobble, strict
/// enough that a scroll (which travels further) never counts.
class SturdyTap extends StatefulWidget {
  const SturdyTap({super.key, required this.onTap, required this.child, this.slop = 48});

  final VoidCallback? onTap;
  final Widget child;
  final double slop;

  @override
  State<SturdyTap> createState() => _SturdyTapState();
}

class _SturdyTapState extends State<SturdyTap> {
  Offset? _down;
  int _pointers = 0;
  bool _multi = false;

  bool _inside(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final local = box.globalToLocal(global);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
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
      onPointerCancel: (_) {
        _pointers = 0;
        _down = null;
      },
      onPointerUp: (e) {
        _pointers = (_pointers - 1).clamp(0, 99);
        final down = _down;
        if (_pointers != 0) return;
        _down = null;
        if (down == null || _multi || widget.onTap == null) return;
        if ((e.position - down).distance > widget.slop) return;
        if (!_inside(e.position)) return;
        widget.onTap!();
      },
      child: widget.child,
    );
  }
}
