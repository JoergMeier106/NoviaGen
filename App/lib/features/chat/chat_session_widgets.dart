import 'package:flutter/material.dart';

import 'package:flutter_app/features/chat/chat_time_formatters.dart';
import 'package:flutter_app/models/chat_sessions.dart';
class EmptyChatState extends StatelessWidget {
  const EmptyChatState({
    super.key,
    required this.hasModels,
    required this.onCreateSession,
  });

  final bool hasModels;
  final VoidCallback onCreateSession;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chat with an AI',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    !hasModels
                        ? 'No models are available yet.'
                        : 'Start a chat session, switch models when needed, and optionally attach a stored gallery image as context.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: !hasModels
                        ? null
                        : onCreateSession,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('New chat'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SessionRail extends StatelessWidget {
  const SessionRail({
    super.key,
    required this.selectedSessionId,
    required this.loadingSessions,
    required this.sessions,
    required this.onSelect,
    required this.onCreate,
  });

  final String? selectedSessionId;
  final bool loadingSessions;
  final List<ChatSessionRecord> sessions;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('New chat'),
          ),
        ),
        Expanded(
          child: loadingSessions
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final selected = session.id == selectedSessionId;
                    return Card(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        selected: selected,
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          session.lastMessagePreview?.isNotEmpty == true
                              ? session.lastMessagePreview!
                              : session.modelName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          compactChatTimeLabel(
                            session.lastMessageAt ?? session.updatedAt,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: () => onSelect(session.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
