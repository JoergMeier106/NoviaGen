import 'package:flutter/material.dart';

import 'package:flutter_app/models/prompts.dart';
import 'package:flutter_app/features/prompts/named_prompt_library_page.dart';


class AutoPromptBasePromptsPage extends StatelessWidget {
  const AutoPromptBasePromptsPage({
    super.key,
    required this.changes,
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
    required this.savedPrompts,
    required this.updateCurrentPrompt,
    required this.createPrompt,
    required this.updatePrompt,
    required this.deletePrompt,
  });

  final Listenable changes;
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
  final List<SavedPrompt> Function() savedPrompts;
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: changes,
      builder: (context, _) => NamedPromptLibraryPage<SavedPrompt>(
        pageTitle: pageTitle,
        currentPromptTitle: currentPromptTitle,
        currentPrompt: currentPrompt,
        currentPromptHintText: currentPromptHintText,
        currentPromptDescription: currentPromptDescription,
        savedPromptsTitle: savedPromptsTitle,
        savedPromptsDescription: savedPromptsDescription,
        emptyCurrentPromptText: emptyCurrentPromptText,
        currentPromptEditorTitle: currentPromptEditorTitle,
        createButtonLabel: createButtonLabel,
        prompts: savedPrompts,
        updateCurrentPrompt: updateCurrentPrompt,
        createPrompt: createPrompt,
        updatePrompt: updatePrompt,
        deletePrompt: deletePrompt,
        buildPrompt:
            ({
              required String id,
              required String name,
              required String prompt,
            }) => SavedPrompt(id: id, name: name, prompt: prompt),
        promptFieldHintText: 'Add reusable instructions for auto-prompting.',
      ),
    );
  }
}
