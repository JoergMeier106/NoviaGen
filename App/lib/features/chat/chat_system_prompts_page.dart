import 'package:flutter/material.dart';

import 'package:noviagen/models/chat_sessions.dart';
import 'package:noviagen/models/prompts.dart';
import 'package:noviagen/features/prompts/named_prompt_library_page.dart';
import 'package:noviagen/features/chat/chat_view_model.dart';

class ChatSystemPromptsPage extends StatelessWidget {
  const ChatSystemPromptsPage({
    super.key,
    required this.sessionId,
    required this.viewModel,
  });

  final String sessionId;
  final ChatViewModel viewModel;

  ChatSessionRecord? _session() {
    for (final session in viewModel.sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final session = _session();
        if (session == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('System prompts')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This chat session is no longer available.'),
              ),
            ),
          );
        }

        return NamedPromptLibraryPage<ChatSystemPrompt>(
          pageTitle: 'System prompts',
          currentPromptTitle: 'Current chat prompt',
          currentPrompt: () => session.systemMessage,
          currentPromptHintText:
              'Add instructions that should guide this chat session.',
          currentPromptDescription:
              'This system message is applied to the current chat session.',
          savedPromptsTitle: 'Saved prompts',
          savedPromptsDescription:
              'Store reusable system prompts here, then apply one to the current chat whenever you want.',
          emptyCurrentPromptText:
              'No system prompt is active for this chat yet.',
          currentPromptEditorTitle: 'System message',
          createButtonLabel: 'Create system prompt',
          prompts: () => viewModel.chatSystemPrompts,
          updateCurrentPrompt: (value) => viewModel.updateSystemMessage(
            sessionId: session.id,
            systemMessage: value.trim(),
          ),
          createPrompt: viewModel.createChatSystemPromptAndPersist,
          updatePrompt: viewModel.updateChatSystemPromptAndPersist,
          deletePrompt: viewModel.deleteChatSystemPromptAndPersist,
          buildPrompt:
              ({
                required String id,
                required String name,
                required String prompt,
              }) => ChatSystemPrompt(id: id, name: name, prompt: prompt),
          activeChipLabel: 'Used in this chat',
          emptySavedPromptsText: 'No saved system prompts yet.',
          newPromptTitle: 'New system prompt',
          editPromptTitle: 'Edit system prompt',
          promptFieldLabel: 'System prompt',
          promptFieldHintText:
              'Add instructions that should guide this chat session.',
          emptyPromptErrorText: 'Enter the system prompt text.',
          deleteDialogTitle: 'Delete system prompt',
        );
      },
    );
  }
}
