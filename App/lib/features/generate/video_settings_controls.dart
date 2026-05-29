import 'package:flutter/material.dart';


class VideoResolutionStepper extends StatelessWidget {
  const VideoResolutionStepper({
    super.key,
    required this.onIncrease,
    required this.onDecrease,
  });

  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message:
          'Increase or decrease width and height together while keeping the aspect ratio.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                tooltip: 'Increase resolution',
                iconSize: 18,
                onPressed: onIncrease,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            SizedBox(
              width: 40,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                tooltip: 'Decrease resolution',
                iconSize: 18,
                onPressed: onDecrease,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
