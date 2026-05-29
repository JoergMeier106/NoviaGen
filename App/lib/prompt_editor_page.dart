import 'package:flutter/material.dart';


class PromptEditorPage extends StatefulWidget {
  const PromptEditorPage({
    super.key,
    required this.title,
    required this.initialValue,
    required this.hintText,
    this.description,
  });

  final String title;
  final String initialValue;
  final String hintText;
  final String? description;

  @override
  State<PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends State<PromptEditorPage> {
  late final TextEditingController _controller;
  late final ScrollController _editorScrollController;
  late List<String> _history;
  late String _lastRecordedText;
  int _historyIndex = 0;
  bool _applyingHistory = false;

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _editorScrollController = ScrollController();
    _history = <String>[widget.initialValue];
    _lastRecordedText = widget.initialValue;
    _controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (_applyingHistory) {
      return;
    }
    final text = _controller.text;
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
    _controller.value = TextEditingValue(
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

  void _save() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final description = widget.description?.trim();
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
            onPressed: () => _controller.clear(),
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
          ),
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: 'Save',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description != null && description.isNotEmpty) ...[
                Text(description),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: Scrollbar(
                  controller: _editorScrollController,
                  thumbVisibility: true,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: null,
                    maxLines: null,
                    expands: true,
                    scrollController: _editorScrollController,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
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
