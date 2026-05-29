import 'package:flutter/material.dart';


class TagFilterSection extends StatelessWidget {
  const TagFilterSection({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.allTags,
    required this.selectedTags,
    required this.onToggle,
  });

  final String title;
  final String emptyLabel;
  final List<String> allTags;
  final List<String> selectedTags;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (allTags.isEmpty)
          Text(emptyLabel, style: Theme.of(context).textTheme.bodyMedium)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allTags
                .map(
                  (tag) => FilterChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    selected: selectedTags.contains(tag),
                    onSelected: (_) => onToggle(tag),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}
