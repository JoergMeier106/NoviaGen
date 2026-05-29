import 'dart:io';

import 'package:flutter/material.dart';

import 'package:noviagen/models/chat_attachments.dart';
class ChatAttachmentGallery extends StatelessWidget {
  const ChatAttachmentGallery({super.key, required this.attachments});

  final List<ChatAttachmentRecord> attachments;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 144,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) => AttachmentPreviewCard(
          attachment: attachments[index],
          width: 176,
          showLabel: attachments.length > 1,
        ),
      ),
    );
  }
}

class ComposerAttachmentTile extends StatelessWidget {
  const ComposerAttachmentTile({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  final ChatAttachmentRecord attachment;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AttachmentPreviewCard(
          attachment: attachment,
          width: 92,
          showLabel: false,
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AttachmentPreviewCard extends StatelessWidget {
  const AttachmentPreviewCard({
    super.key,
    required this.attachment,
    required this.width,
    required this.showLabel,
  });

  final ChatAttachmentRecord attachment;
  final double width;
  final bool showLabel;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _AttachmentImage(attachment: attachment)),
              if (showLabel)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    attachment.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentImage extends StatelessWidget {
  const _AttachmentImage({required this.attachment});

  final ChatAttachmentRecord attachment;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (attachment.localPath?.isNotEmpty ?? false) {
      return Image.file(
        File(attachment.localPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }
    return Image.network(
      attachment.previewUrl ?? '',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}
