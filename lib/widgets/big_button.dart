import 'package:flutter/material.dart';

import '../theme.dart';
import 'sturdy_tap.dart';

/// A large, calm, high-contrast button. Big tap target and clear label —
/// the primary interaction element across the app.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.emoji,
    this.color = AppColors.primary,
    this.enabled = true,
  });

  final String label;
  final String? emoji;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SturdyTap(
        onTap: enabled ? onTap : null,
        child: Material(
        color: enabled ? color : AppColors.border,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          // The ripple only; the press itself is judged by SturdyTap,
          // which forgives a wobbling finger.
          onTap: enabled ? () {} : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (emoji != null) ...[
                  Text(emoji!, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: enabled ? Colors.white : AppColors.textSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
