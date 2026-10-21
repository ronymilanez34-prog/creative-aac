import 'package:flutter/material.dart';

import '../theme.dart';
import 'quick_bar.dart';

/// A quick-fire message takes over the whole screen: everything pauses, the
/// message is unmissable (also to a partner across the room), and nothing
/// moves until the user chooses to return. Help/pain get the loud styling;
/// stop/break/space get a calm one.
///
/// Shared by every creation screen (moved out of companion_screen.dart,
/// 21.10, unchanged), so the emergency strip behaves the same everywhere.
class QuickFireOverlay extends StatelessWidget {
  const QuickFireOverlay({super.key, required this.fire, required this.onDismiss});

  final QuickFire fire;
  final VoidCallback onDismiss;

  bool get _urgent => fire.label == 'עזרה' || fire.label == 'כואב לי';

  @override
  Widget build(BuildContext context) {
    final bg = _urgent ? const Color(0xFFB4483C) : AppColors.primaryDark;
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: bg,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(fire.emoji, style: const TextStyle(fontSize: 96)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                fire.spoken,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              _urgent ? 'לחצו בכל מקום כשהעזרה הגיעה' : 'לחצו כשמוכנים להמשיך',
              style: TextStyle(
                fontSize: 17,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
