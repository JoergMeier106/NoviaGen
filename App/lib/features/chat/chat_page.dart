import 'dart:async';

import 'package:flutter/material.dart';

import 'package:noviagen/models/chat_sessions.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/chat/chat_conversation_view.dart';
import 'package:noviagen/features/chat/chat_context_image_picker.dart';
import 'package:noviagen/features/chat/chat_session_widgets.dart';
import 'package:noviagen/features/chat/chat_system_prompts_page.dart';
import 'package:noviagen/features/chat/chat_tools_page.dart';

import 'package:provider/provider.dart';
import 'package:noviagen/features/chat/chat_view_model.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatViewModel>(
      builder: (context, viewModel, _) => _ChatPageBody(viewModel: viewModel),
    );
  }
}

class _ChatPageBody extends StatefulWidget {
  const _ChatPageBody({required this.viewModel});

  final ChatViewModel viewModel;

  @override
  State<_ChatPageBody> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPageBody> {
  static const double _scrollToBottomThreshold = 160;

  late final TextEditingController _composerController;
  late final ScrollController _messagesScrollController;
  late final Listenable _changes;
  bool _updatingController = false;
  bool _showScrollToBottomButton = false;
  final Set<String> _expandedThinkingMessageIds = <String>{};
  final Set<String> _expandedToolMessageIds = <String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  int _handledScrollToChatMessageRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController(text: widget.viewModel.draft);
    _messagesScrollController = ScrollController();
    _messagesScrollController.addListener(_handleMessagesScrolled);
    _composerController.addListener(_handleComposerChanged);
    _changes = widget.viewModel;
    _changes.addListener(_handleStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPendingThinkingExpansion();
      unawaited(widget.viewModel.ensureReady());
      unawaited(widget.viewModel.loadTools());
      unawaited(widget.viewModel.loadJobs());
      unawaited(widget.viewModel.loadHealth(silent: true));
    });
  }

  @override
  void dispose() {
    _changes.removeListener(_handleStateChanged);
    _messagesScrollController.removeListener(_handleMessagesScrolled);
    _messagesScrollController.dispose();
    _composerController
      ..removeListener(_handleComposerChanged)
      ..dispose();
    super.dispose();
  }

  void _handleStateChanged() {
    if (!mounted) {
      return;
    }
    _syncPendingThinkingExpansion();
  }

  void _syncPendingThinkingExpansion() {
    final messages = widget.viewModel.activeMessages;
    final messageIds = messages.map((message) => message.id).toSet();
    final removedIds = _expandedThinkingMessageIds
        .where((id) => !messageIds.contains(id))
        .toList();
    if (removedIds.isEmpty) {
      return;
    }
    _expandedThinkingMessageIds.removeAll(removedIds);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncComposerFromState();
    _maybeScrollToRequestedMessage();

    final session = widget.viewModel.selectedSession;
    final isWide = MediaQuery.of(context).size.width >= 960;
    final body = session == null
        ? EmptyChatState(
            hasModels: widget.viewModel.items.isNotEmpty,
            onCreateSession: () => unawaited(widget.viewModel.createSession()),
          )
        : ChatConversationView(
            viewModel: widget.viewModel,
            session: session,
            expandedThinkingMessageIds: _expandedThinkingMessageIds,
            expandedToolMessageIds: _expandedToolMessageIds,
            composerController: _composerController,
            messagesScrollController: _messagesScrollController,
            messageKeys: _messageKeys,
            onToggleThinking: _toggleThinking,
            onToggleTools: _toggleTools,
            onOpenSessionPicker: () => _openSessionPicker(context),
            onOpenModelPicker: widget.viewModel.sendingMessage
                ? null
                : () => _openModelPicker(context),
            onOpenContextImagePicker: () => _openContextImagePicker(context),
            onOpenTools: () => _openTools(context),
            onRenameSession: () => _renameSession(context, session),
            onOpenSystemPrompts: () => _openSystemPrompts(context, session),
            onDeleteSession: () => _confirmDeleteSession(context, session),
            onSend: () => unawaited(widget.viewModel.sendMessage()),
            onStop: () => unawaited(widget.viewModel.abortMessage()),
            showScrollToBottomButton: _showScrollToBottomButton,
            onScrollToBottom: _scrollToBottom,
          );

    if (!isWide) {
      return body;
    }

    return Row(
      children: [
        SizedBox(
          width: 312,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: SafeArea(
              right: false,
              child: SessionRail(
                selectedSessionId: session?.id,
                loadingSessions: widget.viewModel.loadingSessions,
                sessions: widget.viewModel.sessions,
                onSelect: (sessionId) =>
                    unawaited(widget.viewModel.selectSession(sessionId)),
                onCreate: () => unawaited(widget.viewModel.createSession()),
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ],
    );
  }

  void _maybeScrollToRequestedMessage() {
    if (_handledScrollToChatMessageRequestCount ==
        widget.viewModel.scrollToChatMessageRequestCount) {
      return;
    }
    _handledScrollToChatMessageRequestCount =
        widget.viewModel.scrollToChatMessageRequestCount;
    final messageId = widget.viewModel.scrollToChatMessageId;
    if (messageId == null || messageId.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetKey = _messageKeys[messageId];
      final targetContext = targetKey?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (_messagesScrollController.hasClients) {
        _scrollToBottom();
      }
      _handleMessagesScrolled();
    });
  }

  void _handleMessagesScrolled() {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    final distanceFromBottom =
        _messagesScrollController.position.maxScrollExtent -
        _messagesScrollController.offset;
    final nextValue = distanceFromBottom > _scrollToBottomThreshold;
    if (nextValue == _showScrollToBottomButton || !mounted) {
      return;
    }
    setState(() {
      _showScrollToBottomButton = nextValue;
    });
  }

  void _scrollToBottom() {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    _messagesScrollController.animateTo(
      _messagesScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleComposerChanged() {
    if (_updatingController) {
      return;
    }
    widget.viewModel.setDraft(_composerController.text);
  }

  void _syncComposerFromState() {
    final draft = widget.viewModel.draft;
    if (_composerController.text == draft) {
      return;
    }
    _updatingController = true;
    _composerController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _updatingController = false;
  }

  void _toggleThinking(String messageId) {
    setState(() {
      if (_expandedThinkingMessageIds.contains(messageId)) {
        _expandedThinkingMessageIds.remove(messageId);
      } else {
        _expandedThinkingMessageIds.add(messageId);
      }
    });
  }

  void _toggleTools(String messageId) {
    setState(() {
      if (_expandedToolMessageIds.contains(messageId)) {
        _expandedToolMessageIds.remove(messageId);
      } else {
        _expandedToolMessageIds.add(messageId);
      }
    });
  }

  Future<void> _openSessionPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SessionRail(
          selectedSessionId: widget.viewModel.selectedSessionId,
          loadingSessions: widget.viewModel.loadingSessions,
          sessions: widget.viewModel.sessions,
          onSelect: (sessionId) async {
            Navigator.of(context).pop();
            await widget.viewModel.selectSession(sessionId);
          },
          onCreate: () async {
            Navigator.of(context).pop();
            await widget.viewModel.createSession();
          },
        ),
      ),
    );
  }

  Future<void> _openModelPicker(BuildContext context) async {
    final session = widget.viewModel.selectedSession;
    if (session == null) {
      return;
    }
    final modelName = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final model in widget.viewModel.items)
              InkWell(
                onTap: () => Navigator.of(context).pop(model.name),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          model.name == session.modelName
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (model.isLoaded) 'Loaded',
                                if ((model.details['parameter_size'] as String?)
                                        ?.isNotEmpty ??
                                    false)
                                  model.details['parameter_size'] as String,
                                if (model.modelContextLength != null)
                                  '${model.modelContextLength} ctx',
                              ].join(' • '),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (model.capabilities.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final capability in model.capabilities)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        _chatCapabilityLabel(capability),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (modelName != null &&
        modelName != session.modelName &&
        context.mounted) {
      await widget.viewModel.updateSelectedModel(modelName);
    }
  }

  Future<void> _renameSession(
    BuildContext context,
    ChatSessionRecord session,
  ) async {
    final controller = TextEditingController(text: session.title);
    final updatedTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updatedTitle != null && updatedTitle.isNotEmpty && context.mounted) {
      await widget.viewModel.renameSession(
        sessionId: session.id,
        title: updatedTitle,
      );
    }
  }

  Future<void> _confirmDeleteSession(
    BuildContext context,
    ChatSessionRecord session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chat'),
        content: Text('Delete "${session.title}" and its messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await widget.viewModel.deleteSession(session.id);
    }
  }

  Future<void> _openSystemPrompts(
    BuildContext context,
    ChatSessionRecord session,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChatSystemPromptsPage(
          sessionId: session.id,
          viewModel: widget.viewModel,
        ),
      ),
    );
  }

  Future<void> _openTools(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChatToolsPage(
          viewModel: widget.viewModel,
          sendingMessage: widget.viewModel.sendingMessage,
        ),
      ),
    );
  }

  Future<void> _openContextImagePicker(BuildContext context) async {
    final selected = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ChatContextImagePicker(viewModel: widget.viewModel),
      ),
    );
    if (selected is List<ImageRecord> && context.mounted) {
      widget.viewModel.addImages(selected);
    }
  }
}

String _chatCapabilityLabel(String capability) {
  final normalized = capability.trim().toLowerCase();
  return switch (normalized) {
    'vision' => 'Vision',
    'tools' => 'Tools',
    'thinking' => 'Thinking',
    'audio' => 'Audio',
    _ => capability,
  };
}
