import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The waiting sign: a brush that slowly circles, trailing a stroke of
/// paint. One continuous motion — no blinking, no spinner, no restart —
/// the same picture in every place the app waits (the companion's turn,
/// the painter, the picture builder). Movement says "something is being
/// made"; sameness keeps it predictable (field 18.10: motion over
/// dimming).
class PainterWait extends StatefulWidget {
  const PainterWait({
    super.key,
    this.width = 64,
    this.height = 44,
    this.color = AppColors.accent,
    this.paperColor,
  });

  final double width;
  final double height;

  /// The paint's colour.
  final Color color;

  /// Background of the little canvas; null = none.
  final Color? paperColor;

  @override
  State<PainterWait> createState() => _PainterWaitState();
}

class _PainterWaitState extends State<PainterWait>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _BrushPainter(
              t: _c.value,
              color: widget.color,
              paper: widget.paperColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  const _BrushPainter({required this.t, required this.color, this.paper});

  /// 0..1, one lap of the brush.
  final double t;
  final Color color;
  final Color? paper;

  // The brush walks an ellipse inside the canvas; the stroke is the arc
  // it covered most recently (a fixed-length trail that never resets).
  static const _trail = 0.42;

  Offset _at(double u, Size s) {
    final a = u * 2 * math.pi;
    return Offset(
      s.width / 2 + math.cos(a) * s.width * 0.34,
      s.height / 2 + math.sin(a) * s.height * 0.30,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (paper != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()..color = paper!,
      );
    }
    final strokeWidth = size.height * 0.16;
    // The trail fades toward its tail by being drawn in short, lighter
    // segments — a stroke that thins out, not a line that jumps.
    const segments = 14;
    for (var i = 0; i < segments; i++) {
      final u0 = t - _trail + _trail * i / segments;
      final u1 = t - _trail + _trail * (i + 1) / segments;
      final alpha = 0.15 + 0.85 * (i + 1) / segments;
      final path = Path()..moveTo(_at(u0, size).dx, _at(u0, size).dy);
      const steps = 3;
      for (var k = 1; k <= steps; k++) {
        final p = _at(u0 + (u1 - u0) * k / steps, size);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * (0.5 + 0.5 * (i + 1) / segments)
          ..strokeCap = StrokeCap.round,
      );
    }
    // The brush: a short handle angled along the path, with a dark tip at
    // the head of the stroke.
    final head = _at(t, size);
    final ahead = _at(t + 0.02, size);
    final dir = (ahead - head);
    final n = dir.distance == 0 ? const Offset(1, 0) : dir / dir.distance;
    final handleLen = size.height * 0.55;
    final tip = head;
    final end = head - n * handleLen + Offset(0, -size.height * 0.35);
    canvas.drawLine(
      tip,
      end,
      Paint()
        ..color = const Color(0xFF8B6B4A)
        ..strokeWidth = strokeWidth * 0.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tip, strokeWidth * 0.75, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BrushPainter old) =>
      old.t != t || old.color != color || old.paper != paper;
}
