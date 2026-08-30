import 'package:flutter/material.dart';

import '../models/story.dart';
import '../theme.dart';
import 'board_image.dart';

/// A selectable card for one [Choice]: big emoji + label, with a clear
/// selected state. Used in the story-building steps.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final Choice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: choice.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 4 : 2,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: FittedBox(
                  child: BoardImage(
                    imagePath: choice.imagePath,
                    emoji: choice.emoji,
                    size: 60,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                choice.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primaryDark : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
