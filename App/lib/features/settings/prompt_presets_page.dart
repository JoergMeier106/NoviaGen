import 'package:flutter/material.dart';

import 'package:flutter_app/models/prompts.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';

import 'package:flutter_app/features/settings/settings_view_model.dart';

class PromptPresetsPage extends StatefulWidget {
  const PromptPresetsPage({
    super.key,
    required this.viewModel,
  });

  final SettingsViewModel viewModel;

  @override
  State<PromptPresetsPage> createState() => _PromptPresetsPageState();
}

class _PromptPresetsPageState extends State<PromptPresetsPage> {
  Future<void> _showPresetEditor({PromptPreset? preset}) async {
    final existingNames = widget.viewModel.presets
        .where((item) => item.id != preset?.id)
        .map((item) => item.name)
        .toList();
    final result = await showDialog<_PromptPresetDraft>(
      context: context,
      builder: (dialogContext) => _PromptPresetEditorDialog(
        preset: preset,
        existingNames: existingNames,
      ),
    );
    if (result == null) {
      return;
    }
    if (preset == null) {
      await widget.viewModel.createPresetAndPersist(
        name: result.name,
        positivePrompt: result.positivePrompt,
        negativePrompt: result.negativePrompt,
      );
    } else {
      await widget.viewModel.updatePresetAndPersist(
        id: preset.id,
        name: result.name,
        positivePrompt: result.positivePrompt,
        negativePrompt: result.negativePrompt,
      );
    }
  }

  Future<void> _confirmDelete(PromptPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete prompt preset'),
        content: Text('Delete "${preset.name}"?'),
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
    if (confirmed != true) {
      return;
    }
    await widget.viewModel.deletePresetAndPersist(preset.id);
  }

  @override
  Widget build(BuildContext context) {
    final presets = widget.viewModel.presets;
    return Scaffold(
          appBar: AppBar(
            title: const Text('Prompt presets'),
            actions: [
              IconButton(
                onPressed: () => _showPresetEditor(),
                icon: const Icon(Icons.add),
                tooltip: 'Add preset',
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InfoCard(
                title: 'Saved prompt pairs',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create named positive and negative prompt pairs here, then select them separately in the image and video generation forms.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (presets.isEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'No prompt presets yet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _showPresetEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Create prompt preset'),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      ...presets.map((preset) {
                        final selectedForImage =
                            widget.viewModel.selectedImagePresetId ==
                            preset.id;
                        final selectedForVideo =
                            widget.viewModel.selectedVideoPresetId ==
                            preset.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              preset.name,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                if (selectedForImage)
                                                  const Chip(
                                                    label: Text(
                                                      'Used for image',
                                                    ),
                                                  ),
                                                if (selectedForVideo)
                                                  const Chip(
                                                    label: Text(
                                                      'Used for video',
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            _showPresetEditor(preset: preset),
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Edit preset',
                                      ),
                                      IconButton(
                                        onPressed: () => _confirmDelete(preset),
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Delete preset',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Positive',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    preset.positivePrompt.isEmpty
                                        ? 'Empty'
                                        : preset.positivePrompt,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Negative',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    preset.negativePrompt.isEmpty
                                        ? 'Empty'
                                        : preset.negativePrompt,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
    );
  }
}

class _PromptPresetDraft {
  const _PromptPresetDraft({
    required this.name,
    required this.positivePrompt,
    required this.negativePrompt,
  });

  final String name;
  final String positivePrompt;
  final String negativePrompt;
}

class _PromptPresetEditorDialog extends StatefulWidget {
  const _PromptPresetEditorDialog({
    required this.preset,
    required this.existingNames,
  });

  final PromptPreset? preset;
  final List<String> existingNames;

  @override
  State<_PromptPresetEditorDialog> createState() =>
      _PromptPresetEditorDialogState();
}

class _PromptPresetEditorDialogState extends State<_PromptPresetEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _positiveController;
  late final TextEditingController _negativeController;
  String? _nameErrorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset?.name ?? '');
    _positiveController = TextEditingController(
      text: widget.preset?.positivePrompt ?? '',
    );
    _negativeController = TextEditingController(
      text: widget.preset?.negativePrompt ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _positiveController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedName = _nameController.text.trim();
    final duplicateName = widget.existingNames.any(
      (name) => name.trim().toLowerCase() == trimmedName.toLowerCase(),
    );
    if (trimmedName.isEmpty) {
      setState(() {
        _nameErrorText = 'Enter a preset name.';
      });
      return;
    }
    if (duplicateName) {
      setState(() {
        _nameErrorText = 'Use a different preset name.';
      });
      return;
    }
    Navigator.of(context).pop(
      _PromptPresetDraft(
        name: trimmedName,
        positivePrompt: _positiveController.text,
        negativePrompt: _negativeController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.preset != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit prompt preset' : 'New prompt preset'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Preset name',
                  errorText: _nameErrorText,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _positiveController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Positive prompt',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _negativeController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Negative prompt',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
