import 'package:flutter/material.dart';

import 'package:noviagen/models/chat_sessions.dart';
import 'package:noviagen/features/chat/chat_composer.dart';
import 'package:noviagen/features/chat/chat_message_bubble.dart';
import 'package:noviagen/features/chat/chat_view_model.dart';

class ChatConversationView extends StatelessWidget {
  const ChatConversationView({
    super.key,
    required this.viewModel,
    required this.session,
    required this.expandedThinkingMessageIds,
    required this.expandedToolMessageIds,
    required this.composerController,
    required this.messagesScrollController,
    required this.messageKeys,
    required this.onToggleThinking,
    required this.onToggleTools,
    required this.onOpenSessionPicker,
    required this.onOpenModelPicker,
    required this.onOpenContextImagePicker,
    required this.onOpenTools,
    required this.onRenameSession,
    required this.onOpenSystemPrompts,
    required this.onDeleteSession,
    required this.onSend,
    required this.onStop,
    required this.showScrollToBottomButton,
    required this.onScrollToBottom,
  });

  final ChatViewModel viewModel;
  final ChatSessionRecord session;
  final Set<String> expandedThinkingMessageIds;
  final Set<String> expandedToolMessageIds;
  final TextEditingController composerController;
  final ScrollController messagesScrollController;
  final Map<String, GlobalKey> messageKeys;
  final VoidCallback onOpenSessionPicker;
  final VoidCallback? onOpenModelPicker;
  final VoidCallback onOpenContextImagePicker;
  final VoidCallback onOpenTools;
  final VoidCallback onRenameSession;
  final VoidCallback onOpenSystemPrompts;
  final VoidCallback onDeleteSession;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final bool showScrollToBottomButton;
  final VoidCallback onScrollToBottom;
  final ValueChanged<String> onToggleThinking;
  final ValueChanged<String> onToggleTools;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedModel = viewModel.items
        .where((model) => model.name == session.modelName)
        .firstOrNull;
    final supportsTools = selectedModel?.supportsTools ?? false;
    final hasEnabledTools = viewModel.tools.any(
      (tool) => viewModel.isToolEnabled(tool.id),
    );
    final enabledToolCount = viewModel.tools
        .where((tool) => viewModel.isToolEnabled(tool.id))
        .length;
    return Column(
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerLowest,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onOpenSessionPicker,
                    icon: const Icon(Icons.add_comment),
                    tooltip: 'Sessions',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ActionChip(
                              avatar: const Icon(
                                Icons.memory_outlined,
                                size: 18,
                              ),
                              label: Text(session.modelName),
                              onPressed: onOpenModelPicker,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: hasEnabledTools ? theme.colorScheme.primary : null,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'attach':
                          onOpenContextImagePicker();
                          break;
                        case 'tools':
                          onOpenTools();
                          break;
                        case 'rename':
                          onRenameSession();
                          break;
                        case 'system':
                          onOpenSystemPrompts();
                          break;
                        case 'delete':
                          onDeleteSession();
                          break;
                        default:
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'attach',
                        enabled: !viewModel.sendingMessage,
                        child: const Row(
                          children: [
                            Icon(Icons.add_photo_alternate_outlined),
                            SizedBox(width: 12),
                            Expanded(child: Text('Add image')),
                          ],
                        ),
                      ),
                      if (supportsTools)
                        PopupMenuItem<String>(
                          value: 'tools',
                          child: Row(
                            children: [
                              Icon(
                                Icons.extension_outlined,
                                color: hasEnabledTools
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: Text('MCP tools')),
                              if (viewModel.loadingTools)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else if (viewModel.toolsError != null)
                                Icon(
                                  Icons.error_outline,
                                  color: theme.colorScheme.error,
                                )
                              else if (enabledToolCount > 0)
                                Text(
                                  '$enabledToolCount',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                      PopupMenuItem<String>(
                        value: 'system',
                        child: Text('System prompts'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: viewModel.loadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : viewModel.activeMessages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No messages yet. Start the conversation below.',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: messagesScrollController,
                        reverse: false,
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                        itemCount: viewModel.activeMessages.length,
                        itemBuilder: (context, index) {
                          final messages = viewModel.activeMessages;
                          final message = messages[index];
                          final messageKey = messageKeys.putIfAbsent(
                            message.id,
                            () => GlobalKey(debugLabel: message.id),
                          );
                          final isPendingAssistantMessage =
                              viewModel.sendingMessage &&
                              message.isAssistant &&
                              index == messages.length - 1;
                          return ChatBubble(
                            key: messageKey,
                            message: message,
                            isPending: isPendingAssistantMessage,
                            expandedThinking: expandedThinkingMessageIds
                                .contains(message.id),
                            expandedTools: expandedToolMessageIds.contains(
                              message.id,
                            ),
                            onToggleThinking:
                                message.thinking == null ||
                                    message.thinking!.isEmpty
                                ? null
                                : () => onToggleThinking(message.id),
                            onToggleTools: message.toolTraces.isEmpty
                                ? null
                                : () => onToggleTools(message.id),
                          );
                        },
                      ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: AnimatedScale(
                  scale: showScrollToBottomButton ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _ChatScrollToBottomButton(
                    onTap: showScrollToBottomButton ? onScrollToBottom : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ChatComposer(
          composerController: composerController,
          sendingMessage: viewModel.sendingMessage,
          attachments: viewModel.attachments,
          onRemoveAttachment: viewModel.remove,
          onSend: onSend,
          onStop: onStop,
        ),
      ],
    );
  }
}

class _ChatScrollToBottomButton extends StatelessWidget {
  const _ChatScrollToBottomButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'chat-scroll-bottom',
      onPressed: onTap,
      child: const Icon(Icons.vertical_align_bottom),
    );
  }
}
