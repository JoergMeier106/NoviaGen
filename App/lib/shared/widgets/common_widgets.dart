import 'package:flutter/material.dart';


class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActiveChip extends StatelessWidget {
  const ActiveChip({super.key, required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close, size: 18),
    );
  }
}

class PickerTile extends StatelessWidget {
  const PickerTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(title),
      trailing: selected ? const Icon(Icons.check) : null,
    );
  }
}

class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorDetailLine extends StatelessWidget {
  const ErrorDetailLine({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
    this.selectable = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool selectable;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style =
        (monospace
                ? Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')
                : Theme.of(context).textTheme.bodyMedium)
            ?.copyWith(color: valueColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        if (selectable)
          SelectableText(value, style: style)
        else
          Text(value, style: style),
      ],
    );
  }
}

class SystemMetricTile extends StatelessWidget {
  const SystemMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            helper,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class RatingBar extends StatelessWidget {
  const RatingBar({super.key, required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('Rating', style: Theme.of(context).textTheme.titleSmall),
        ),
        for (var index = 1; index <= 5; index++)
          IconButton(
            onPressed: () => onChanged(index == rating ? 0 : index),
            icon: Icon(
              index <= rating ? Icons.star : Icons.star_border,
              color: index <= rating
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.outline,
            ),
            tooltip: '$index stars',
          ),
      ],
    );
  }
}

class MediaFullscreenButton extends StatelessWidget {
  const MediaFullscreenButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.fullscreen),
        color: Colors.white,
        tooltip: 'Fullscreen',
      ),
    );
  }
}

class LogScrollToBottomButton extends StatelessWidget {
  const LogScrollToBottomButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'logs-scroll-bottom',
      onPressed: onTap,
      child: const Icon(Icons.vertical_align_bottom),
    );
  }
}
