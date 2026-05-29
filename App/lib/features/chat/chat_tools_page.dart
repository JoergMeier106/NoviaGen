import 'package:flutter/material.dart';

import 'package:noviagen/features/chat/chat_view_model.dart';
import 'package:noviagen/models/chat_tools.dart';

class ChatToolsPage extends StatelessWidget {
  const ChatToolsPage({
    super.key,
    required this.viewModel,
    required this.sendingMessage,
  });

  final ChatViewModel viewModel;
  final bool sendingMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => _ChatToolsPageBody(
        viewModel: viewModel,
        sendingMessage: sendingMessage,
      ),
    );
  }
}

class _ChatToolsPageBody extends StatelessWidget {
  const _ChatToolsPageBody({
    required this.viewModel,
    required this.sendingMessage,
  });

  final ChatViewModel viewModel;
  final bool sendingMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _groupToolsByServer(viewModel.tools);
    return Scaffold(
      appBar: AppBar(title: const Text('MCP tools')),
      body: SafeArea(
        child: viewModel.loadingTools
            ? const Center(child: CircularProgressIndicator())
            : viewModel.toolsError != null
            ? _ToolsMessage(
                icon: Icons.error_outline,
                text: viewModel.toolsError!,
              )
            : groups.isEmpty
            ? const _ToolsMessage(
                icon: Icons.extension_off_outlined,
                text: 'No MCP tools discovered.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final enabledCount = group.tools
                      .where((tool) => viewModel.isToolEnabled(tool.id))
                      .length;
                  final allEnabled = enabledCount == group.tools.length;
                  final serverValue = enabledCount == 0
                      ? false
                      : allEnabled
                      ? true
                      : null;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Row(
                            children: [
                              Checkbox(
                                tristate: true,
                                value: serverValue,
                                onChanged: sendingMessage
                                    ? null
                                    : (_) => _setServerEnabled(
                                        viewModel,
                                        group.tools,
                                        !allEnabled,
                                      ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  group.serverName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                '$enabledCount/${group.tools.length}',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        for (final tool in group.tools)
                          SwitchListTile(
                            value: viewModel.isToolEnabled(tool.id),
                            onChanged: sendingMessage
                                ? null
                                : (value) =>
                                      viewModel.setToolEnabled(tool.id, value),
                            secondary: const Icon(Icons.extension_outlined),
                            title: Text(
                              _toolName(tool),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: tool.description.trim().isEmpty
                                ? Text(tool.id)
                                : Text(
                                    tool.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _ToolsMessage extends StatelessWidget {
  const _ToolsMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

void _setServerEnabled(
  ChatViewModel viewModel,
  List<ChatToolInfo> tools,
  bool value,
) {
  for (final tool in tools) {
    viewModel.setToolEnabled(tool.id, value);
  }
}

class _ToolServerGroup {
  const _ToolServerGroup({required this.serverName, required this.tools});

  final String serverName;
  final List<ChatToolInfo> tools;
}

List<_ToolServerGroup> _groupToolsByServer(List<ChatToolInfo> tools) {
  final grouped = <String, List<ChatToolInfo>>{};
  for (final tool in tools) {
    final serverName = tool.serverName.trim().isEmpty
        ? 'Unspecified server'
        : tool.serverName.trim();
    grouped.putIfAbsent(serverName, () => <ChatToolInfo>[]).add(tool);
  }
  final groups = grouped.entries
      .map(
        (entry) => _ToolServerGroup(
          serverName: entry.key,
          tools: [...entry.value]
            ..sort((a, b) => _toolName(a).compareTo(_toolName(b))),
        ),
      )
      .toList();
  groups.sort((a, b) => a.serverName.compareTo(b.serverName));
  return groups;
}

String _toolName(ChatToolInfo tool) {
  final name = tool.name.replaceAll('_', ' ').trim();
  return name.isEmpty ? tool.id : name;
}
