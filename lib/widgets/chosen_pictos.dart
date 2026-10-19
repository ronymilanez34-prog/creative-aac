import 'package:flutter/material.dart';

import '../theme.dart';

/// One pictogram the creator just chose — its emoji and its word.
class ChosenPicto {
  const ChosenPicto({required this.emoji, required this.label, required this.seq});

  final String emoji;
  final String label;

  /// Monotonic order of choice; the painter clears every picto up to the
  /// one it started with once their picture is on screen.
  final int seq;
}

/// The chosen pictograms, big, where the picture is (or will be).
///
/// This IS the waiting state (pilot 19.10): what the creator just chose
/// stands on the stage at once — over the previous picture when there is
/// one, "entering" it — and leaves the moment the picture that holds it
/// arrives. Nothing abstract spins; the wait shows the creation itself.
/// Motion is calm and continuous: a soft entrance, then a slow breath.
class ChosenPictos extends StatelessWidget {
  const ChosenPictos({
    super.key,
    required this.pictos,
    this.overPicture = false,
  });

  final List<ChosenPicto> pictos;

  /// Laid over an existing picture (smaller, on a soft card) rather than
  /// standing alone on the empty stage.
  final bool overPicture;

  @override
  Widget build(BuildContext context) {
    final emojiSize = overPicture ? 48.0 : 64.0;
    final labelSize = overPicture ? 18.0 : 22.0;
    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: [
          for (final p in pictos)
            _Enter(
              key: ValueKey(p.seq),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: overPicture ? 0.88 : 0.0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.emoji.trim().isNotEmpty)
                      Text(p.emoji, style: TextStyle(fontSize: emojiSize, height: 1.1)),
                    Text(
                      p.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: labelSize,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Soft entrance (fade + grow, 600ms), then a slow breath — a sign of
/// life that never blinks or jumps.
class _Enter extends StatefulWidget {
  const _Enter({super.key, required this.child});

  final Widget child;

  @override
  State<_Enter> createState() => _EnterState();
}

class _EnterState extends State<_Enter> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _in.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: Listenable.merge([_in, _breath]),
      builder: (_, child) {
        final grow = 0.6 + 0.4 * fade.value;
        final breath = 1.0 + 0.03 * Curves.easeInOut.transform(_breath.value);
        return Opacity(
          opacity: fade.value,
          child: Transform.scale(scale: grow * breath, child: child),
        );
      },
      child: widget.child,
    );
  }
}
