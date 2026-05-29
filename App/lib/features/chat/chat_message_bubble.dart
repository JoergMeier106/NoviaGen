import 'package:flutter/material.dart';

import 'package:noviagen/models/chat_messages.dart';
import 'package:noviagen/features/chat/chat_attachment_preview.dart';
import 'package:noviagen/features/chat/chat_markdown.dart';
import 'package:noviagen/features/chat/chat_time_formatters.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isPending,
    required this.expandedThinking,
    required this.expandedTools,
    required this.onToggleThinking,
    required this.onToggleTools,
  });

  final ChatMessageRecord message;
  final bool isPending;
  final bool expandedThinking;
  final bool expandedTools;
  final VoidCallback? onToggleThinking;
  final VoidCallback? onToggleTools;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alignEnd = message.isUser;
    final bubbleColor = alignEnd
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final textColor = alignEnd
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.effectiveAttachments.isNotEmpty) ...[
                    ChatAttachmentGallery(
                      attachments: message.effectiveAttachments,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (message.content.isNotEmpty)
                    ChatMarkdownMessage(
                      text: message.content,
                      textColor: textColor,
                      bubbleColor: bubbleColor,
                      baseStyle: theme.textTheme.bodyLarge,
                    )
                  else if (isPending && message.thinking?.isNotEmpty != true)
                    const PendingChatDots(),
                  if (message.thinking?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    _ExpandableTraceHeader(
                      label: 'Thinking',
                      expanded: expandedThinking,
                      onTap: onToggleThinking,
                    ),
                    if (expandedThinking)
                      _TracePanel(
                        child: ChatMarkdownMessage(
                          text: message.thinking!,
                          textColor: theme.colorScheme.onSurface,
                          bubbleColor: theme.colorScheme.surface,
                          baseStyle: theme.textTheme.bodyMedium,
                        ),
                      ),
                  ],
                  if (message.toolTraces.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ExpandableTraceHeader(
                      label: message.toolTraces.length == 1
                          ? 'Tool output'
                          : 'Tool outputs (${message.toolTraces.length})',
                      expanded: expandedTools,
                      onTap: onToggleTools,
                    ),
                    if (expandedTools)
                      _TracePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final trace in message.toolTraces) ...[
                              Text(
                                trace.label,
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                trace.content,
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (trace != message.toolTraces.last)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Divider(height: 1),
                                ),
                            ],
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    chatTimeLabel(message.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor.withValues(alpha: 0.78),
                    ),
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

class _ExpandableTraceHeader extends StatelessWidget {
  const _ExpandableTraceHeader({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _TracePanel extends StatelessWidget {
  const _TracePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class PendingChatDots extends StatefulWidget {
  const PendingChatDots({super.key});

  @override
  State<PendingChatDots> createState() => _PendingChatDotsState();
}

class _PendingChatDotsState extends State<PendingChatDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 42,
      height: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final activeDot = (_controller.value * 3).floor() % 3;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(3, (index) {
              final isActive = index == activeDot;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                width: isActive ? 8 : 6,
                height: isActive ? 8 : 6,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isActive ? 0.95 : 0.45),
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
