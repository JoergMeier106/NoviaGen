import 'package:flutter/material.dart';

import 'package:noviagen/models/prompts.dart';
import 'package:noviagen/prompt_editor_page.dart';


class NamedPromptLibraryPage<T extends NamedPromptEntry>
    extends StatefulWidget {
  const NamedPromptLibraryPage({
    super.key,
    required this.pageTitle,
    required this.currentPromptTitle,
    required this.currentPrompt,
    required this.currentPromptHintText,
    required this.currentPromptDescription,
    required this.savedPromptsTitle,
    required this.savedPromptsDescription,
    required this.emptyCurrentPromptText,
    required this.currentPromptEditorTitle,
    required this.createButtonLabel,
    required this.prompts,
    required this.updateCurrentPrompt,
    required this.createPrompt,
    required this.updatePrompt,
    required this.deletePrompt,
    required this.buildPrompt,
    this.activeChipLabel = 'Selected',
    this.emptySavedPromptsText = 'No saved prompts yet.',
    this.newPromptTitle = 'New saved prompt',
    this.editPromptTitle = 'Edit saved prompt',
    this.promptFieldLabel = 'Prompt',
    this.promptFieldHintText = 'Add reusable instructions.',
    this.emptyPromptErrorText = 'Enter the prompt text.',
    this.deleteDialogTitle = 'Delete saved prompt',
    this.saveAsStoredPromptLabel = 'Save as stored prompt',
    this.clearCurrentPromptLabel = 'Clear current prompt',
  });

  final String pageTitle;
  final String currentPromptTitle;
  final String Function() currentPrompt;
  final String currentPromptHintText;
  final String currentPromptDescription;
  final String savedPromptsTitle;
  final String savedPromptsDescription;
  final String emptyCurrentPromptText;
  final String currentPromptEditorTitle;
  final String createButtonLabel;
  final List<T> Function() prompts;
  final Future<void> Function(String value) updateCurrentPrompt;
  final Future<void> Function({required String name, required String prompt})
  createPrompt;
  final Future<void> Function({
    required String id,
    required String name,
    required String prompt,
  })
  updatePrompt;
  final Future<void> Function(String id) deletePrompt;
  final T Function({
    required String id,
    required String name,
    required String prompt,
  })
  buildPrompt;
  final String activeChipLabel;
  final String emptySavedPromptsText;
  final String newPromptTitle;
  final String editPromptTitle;
  final String promptFieldLabel;
  final String promptFieldHintText;
  final String emptyPromptErrorText;
  final String deleteDialogTitle;
  final String saveAsStoredPromptLabel;
  final String clearCurrentPromptLabel;

  @override
  State<NamedPromptLibraryPage<T>> createState() =>
      _NamedPromptLibraryPageState<T>();
}

class _NamedPromptLibraryPageState<T extends NamedPromptEntry>
    extends State<NamedPromptLibraryPage<T>> {
  Future<void> _editCurrentPrompt() async {
    final updatedMessage = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => PromptEditorPage(
          title: widget.currentPromptEditorTitle,
          initialValue: widget.currentPrompt(),
          hintText: widget.currentPromptHintText,
          description: widget.currentPromptDescription,
        ),
      ),
    );
    if (updatedMessage == null) {
      return;
    }
    await widget.updateCurrentPrompt(updatedMessage);
  }

  Future<void> _showPromptEditor({T? prompt, String? initialPrompt}) async {
    final existingNames = widget
        .prompts()
        .where((item) => item.id != prompt?.id)
        .map((item) => item.name)
        .toList();
    final result = await Navigator.of(context).push<_NamedPromptDraft>(
      MaterialPageRoute<_NamedPromptDraft>(
        builder: (context) => _NamedPromptEditorPage(
          title: prompt == null
              ? widget.newPromptTitle
              : widget.editPromptTitle,
          promptName: prompt?.name,
          promptText: prompt?.prompt ?? initialPrompt ?? '',
          existingNames: existingNames,
          promptFieldLabel: widget.promptFieldLabel,
          promptFieldHintText: widget.promptFieldHintText,
          emptyPromptErrorText: widget.emptyPromptErrorText,
        ),
      ),
    );
    if (result == null) {
      return;
    }
    if (prompt == null) {
      await widget.createPrompt(name: result.name, prompt: result.prompt);
      return;
    }
    await widget.updatePrompt(
      id: prompt.id,
      name: result.name,
      prompt: result.prompt,
    );
  }

  Future<void> _applyPrompt(T prompt) async {
    await widget.updateCurrentPrompt(prompt.prompt);
  }

  Future<void> _clearCurrentPrompt() async {
    await widget.updateCurrentPrompt('');
  }

  Future<void> _confirmDelete(T prompt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.deleteDialogTitle),
        content: Text('Delete "${prompt.name}"?'),
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
    if (confirmed == true) {
      await widget.deletePrompt(prompt.id);
    }
  }

  bool _isPromptActive(T prompt) {
    final current = widget.currentPrompt().trim();
    if (current.isEmpty) {
      return false;
    }
    return prompt.prompt.trim() == current;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPrompt = widget.currentPrompt().trim();
    final prompts = widget.prompts();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageTitle),
        actions: [
          IconButton(
            onPressed: () => _showPromptEditor(),
            icon: const Icon(Icons.add),
            tooltip: 'Add prompt',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PromptSection(
            title: widget.currentPromptTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentPrompt.isEmpty
                      ? widget.emptyCurrentPromptText
                      : currentPrompt,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _editCurrentPrompt,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        currentPrompt.isEmpty
                            ? 'Write current prompt'
                            : 'Edit current prompt',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: currentPrompt.isEmpty
                          ? null
                          : () =>
                                _showPromptEditor(initialPrompt: currentPrompt),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(widget.saveAsStoredPromptLabel),
                    ),
                    OutlinedButton.icon(
                      onPressed: currentPrompt.isEmpty
                          ? null
                          : _clearCurrentPrompt,
                      icon: const Icon(Icons.clear),
                      label: Text(widget.clearCurrentPromptLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PromptSection(
            title: widget.savedPromptsTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.savedPromptsDescription,
                  style: theme.textTheme.bodyMedium,
                ),
                if (prompts.isEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.emptySavedPromptsText,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _showPromptEditor(),
                    icon: const Icon(Icons.add),
                    label: Text(widget.createButtonLabel),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  ...prompts.map((prompt) {
                    final isActive = _isPromptActive(prompt);
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prompt.name,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        if (isActive) ...[
                                          const SizedBox(height: 8),
                                          Chip(
                                            label: Text(widget.activeChipLabel),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: isActive
                                        ? null
                                        : () => _applyPrompt(prompt),
                                    child: Text(isActive ? 'Selected' : 'Use'),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _showPromptEditor(
                                      prompt: widget.buildPrompt(
                                        id: prompt.id,
                                        name: prompt.name,
                                        prompt: prompt.prompt,
                                      ),
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Edit prompt',
                                  ),
                                  IconButton(
                                    onPressed: () => _confirmDelete(prompt),
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Delete prompt',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SelectableText(prompt.prompt),
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

class _PromptSection extends StatelessWidget {
  const _PromptSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
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

class _NamedPromptDraft {
  const _NamedPromptDraft({required this.name, required this.prompt});

  final String name;
  final String prompt;
}

class _NamedPromptEditorPage extends StatefulWidget {
  const _NamedPromptEditorPage({
    required this.title,
    required this.promptName,
    required this.promptText,
    required this.existingNames,
    required this.promptFieldLabel,
    required this.promptFieldHintText,
    required this.emptyPromptErrorText,
  });

  final String title;
  final String? promptName;
  final String promptText;
  final List<String> existingNames;
  final String promptFieldLabel;
  final String promptFieldHintText;
  final String emptyPromptErrorText;

  @override
  State<_NamedPromptEditorPage> createState() => _NamedPromptEditorPageState();
}

class _NamedPromptEditorPageState extends State<_NamedPromptEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late final ScrollController _promptScrollController;
  late List<String> _history;
  late String _lastRecordedText;
  int _historyIndex = 0;
  bool _applyingHistory = false;
  String? _nameErrorText;
  String? _promptErrorText;

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.promptName ?? '');
    _promptController = TextEditingController(text: widget.promptText);
    _promptScrollController = ScrollController();
    _history = <String>[widget.promptText];
    _lastRecordedText = widget.promptText;
    _promptController.addListener(_handlePromptChanged);
  }

  @override
  void dispose() {
    _promptController.removeListener(_handlePromptChanged);
    _nameController.dispose();
    _promptController.dispose();
    _promptScrollController.dispose();
    super.dispose();
  }

  void _handlePromptChanged() {
    if (_applyingHistory) {
      return;
    }
    final text = _promptController.text;
    if (text == _lastRecordedText) {
      return;
    }
    if (_historyIndex < _history.length - 1) {
      _history = _history.sublist(0, _historyIndex + 1);
    }
    _history.add(text);
    _historyIndex = _history.length - 1;
    _lastRecordedText = text;
    if (mounted) {
      setState(() {});
    }
  }

  void _applyHistory(int nextIndex) {
    if (nextIndex < 0 ||
        nextIndex >= _history.length ||
        nextIndex == _historyIndex) {
      return;
    }
    final text = _history[nextIndex];
    _applyingHistory = true;
    _historyIndex = nextIndex;
    _lastRecordedText = text;
    _promptController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
    _applyingHistory = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _undo() => _applyHistory(_historyIndex - 1);

  void _redo() => _applyHistory(_historyIndex + 1);

  void _submit() {
    final trimmedName = _nameController.text.trim();
    final trimmedPrompt = _promptController.text.trim();
    final duplicateName = widget.existingNames.any(
      (name) => name.trim().toLowerCase() == trimmedName.toLowerCase(),
    );
    setState(() {
      _nameErrorText = null;
      _promptErrorText = null;
      if (trimmedName.isEmpty) {
        _nameErrorText = 'Enter a prompt name.';
      } else if (duplicateName) {
        _nameErrorText = 'Use a different prompt name.';
      }
      if (trimmedPrompt.isEmpty) {
        _promptErrorText = widget.emptyPromptErrorText;
      }
    });
    if (_nameErrorText != null || _promptErrorText != null) {
      return;
    }
    Navigator.of(
      context,
    ).pop(_NamedPromptDraft(name: trimmedName, prompt: _promptController.text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _canUndo ? _undo : null,
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: _canRedo ? _redo : null,
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
          ),
          IconButton(
            onPressed: () => _promptController.clear(),
            icon: const Icon(Icons.clear),
            tooltip: 'Clear prompt',
          ),
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.check),
            tooltip: widget.promptName == null ? 'Create' : 'Save',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Prompt name',
                  errorText: _nameErrorText,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  controller: _promptScrollController,
                  thumbVisibility: true,
                  child: TextField(
                    controller: _promptController,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: null,
                    maxLines: null,
                    expands: true,
                    scrollController: _promptScrollController,
                    decoration: InputDecoration(
                      labelText: widget.promptFieldLabel,
                      hintText: widget.promptFieldHintText,
                      errorText: _promptErrorText,
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
