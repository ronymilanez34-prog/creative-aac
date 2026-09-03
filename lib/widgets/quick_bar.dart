import 'package:flutter/material.dart';

import '../theme.dart';

/// One quick-fire message: label on the button, [spoken] said aloud.
class QuickFire {
  const QuickFire(this.emoji, this.label, this.spoken);

  final String emoji;
  final String label;
  final String spoken;
}

/// The fixed quick-fire messages. Order and placement NEVER change — motor
/// consistency is the point (response efficiency: the communicative act must
/// be faster than the behaviour it replaces). Fully local: no AI, no network.
const List<QuickFire> kQuickFires = [
  QuickFire('✋', 'עצור', 'עצור בבקשה'),
  QuickFire('⏸️', 'הפסקה', 'אני צריך הפסקה'),
  QuickFire('🆘', 'עזרה', 'אני צריך עזרה'),
  QuickFire('🤕', 'כואב לי', 'כואב לי'),
  QuickFire('🔇', 'חזק מדי', 'זה חזק מדי בשבילי'),
  QuickFire('🚪', 'מרחב', 'אני צריך מרחב'),
];

/// The always-available emergency strip. One tap from anywhere: speaks the
/// message immediately and reports it via [onFire] (the screen logs it and
/// can show a large confirmation of what was said).
class QuickBar extends StatelessWidget {
  const QuickBar({super.key, required this.onFire});

  final ValueChanged<QuickFire> onFire;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: Row(
        children: [
          for (final q in kQuickFires)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Semantics(
                  button: true,
                  label: q.spoken,
                  child: Material(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onFire(q),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 58),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(q.emoji,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                q.label,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                          ],
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
