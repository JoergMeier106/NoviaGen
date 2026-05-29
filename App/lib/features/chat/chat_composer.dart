import 'package:flutter/material.dart';

import 'package:flutter_app/features/chat/chat_attachment_preview.dart';
import 'package:flutter_app/models/chat_attachments.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.composerController,
    required this.sendingMessage,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController composerController;
  final bool sendingMessage;
  final List<ChatAttachmentRecord> attachments;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final canSend =
        !sendingMessage && composerController.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (attachments.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${attachments.length} attachment(s)',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: attachments.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final attachment = attachments[index];
                            return ComposerAttachmentTile(
                              attachment: attachment,
                              onRemove: () =>
                                  onRemoveAttachment(attachment.stableKey),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: composerController,
                    enabled: !sendingMessage,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message the model',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: sendingMessage
                      ? onStop
                      : (canSend ? onSend : null),
                  child: Icon(
                    sendingMessage ? Icons.stop_rounded : Icons.send_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
