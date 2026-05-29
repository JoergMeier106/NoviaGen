import 'package:flutter/material.dart';

import 'package:noviagen/models/media.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';

class MediaTagEditor extends StatefulWidget {
  const MediaTagEditor({
    super.key,
    required this.image,
    required this.suggestedTags,
    required this.onChanged,
    required this.onDeleteTag,
    this.onGenerateTags,
  });

  final ImageRecord image;
  final List<String> suggestedTags;
  final ValueChanged<List<String>> onChanged;
  final Future<void> Function(String) onDeleteTag;
  final Future<void> Function()? onGenerateTags;

  @override
  State<MediaTagEditor> createState() => _MediaTagEditorState();
}

class _MediaTagEditorState extends State<MediaTagEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isAdding = false;
  bool _generatingTags = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableSuggestions = widget.suggestedTags
        .where(
          (tag) => !widget.image.tags.any(
            (existing) => existing.toLowerCase() == tag.toLowerCase(),
          ),
        )
        .toList();

    return InfoCard(
      title: 'Tags',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...widget.image.tags.map(
                (tag) => InputChip(
                  label: Text(tag),
                  onDeleted: () => _removeTag(tag),
                ),
              ),
              if (_isAdding)
                _InlineAddTagChip(
                  controller: _controller,
                  focusNode: _focusNode,
                  onSubmitted: _submitTag,
                  onCancelled: _cancelAdding,
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add tag'),
                  onPressed: _startAdding,
                ),
              if (widget.onGenerateTags != null)
                IconButton(
                  tooltip: 'Generate tags',
                  icon: _generatingTags
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  onPressed: _generatingTags ? null : _generateTags,
                ),
            ],
          ),
          if (availableSuggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Suggestions', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableSuggestions
                  .map(
                    (tag) => InputChip(
                      label: Text(tag),
                      onPressed: () => _addTag(tag),
                      onDeleted: () => _confirmDeleteSuggestion(tag),
                      deleteIcon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _submitTag() {
    final tag = _controller.text.trim();
    if (tag.isEmpty) {
      _cancelAdding();
      return;
    }
    if (widget.image.tags.any(
      (existing) => existing.toLowerCase() == tag.toLowerCase(),
    )) {
      _cancelAdding();
      return;
    }
    _controller.clear();
    setState(() {
      _isAdding = false;
    });
    _addTag(tag);
  }

  void _addTag(String tag) {
    final updated = <String>[...widget.image.tags, tag];
    widget.onChanged(updated);
  }

  void _removeTag(String tag) {
    final updated = widget.image.tags
        .where((item) => item.toLowerCase() != tag.toLowerCase())
        .toList();
    widget.onChanged(updated);
  }

  void _startAdding() {
    setState(() {
      _isAdding = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _generateTags() async {
    final generateTags = widget.onGenerateTags;
    if (generateTags == null || _generatingTags) {
      return;
    }
    setState(() {
      _generatingTags = true;
    });
    try {
      await generateTags();
    } finally {
      if (mounted) {
        setState(() {
          _generatingTags = false;
        });
      }
    }
  }

  void _cancelAdding() {
    _controller.clear();
    if (!_isAdding) {
      return;
    }
    setState(() {
      _isAdding = false;
    });
  }

  Future<void> _confirmDeleteSuggestion(String tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete tag'),
        content: Text('Delete "$tag" from all images?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onDeleteTag(tag);
    }
  }
}

class _InlineAddTagChip extends StatelessWidget {
  const _InlineAddTagChip({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onCancelled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final VoidCallback onCancelled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicWidth(
      child: Container(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'New tag',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => onSubmitted(),
                onTapOutside: (_) => onCancelled(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
