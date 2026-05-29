import 'package:flutter/material.dart';

import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/shared/media_preview.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';
import 'package:flutter_app/features/gallery/media_detail_pages.dart';

import 'package:flutter_app/features/generate/generation_view_model.dart';

class LatestMediaCard extends StatelessWidget {
  const LatestMediaCard({
    super.key,
    required this.viewModel,
    required this.image,
  });

  final GenerationViewModel viewModel;
  final ImageRecord image;

  @override
  Widget build(BuildContext context) {
    final isStored = image.status == 'stored';
    final mediaLabel = image.mediaTypeLabel.toLowerCase();

    Future<void> deleteLatestResult() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(isStored ? 'Delete $mediaLabel' : 'Discard result'),
          content: Text(
            isStored
                ? 'Move this $mediaLabel to deleted media?'
                : 'Discard this latest $mediaLabel result?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(isStored ? 'Delete' : 'Discard'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) {
        return;
      }

      final deletedMessage = await viewModel.deleteStoredImage(
        image.id,
      );
      if (!context.mounted) {
        return;
      }
      final feedbackMessage = deletedMessage ?? viewModel.message;
      if (feedbackMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(feedbackMessage)));
      }
    }

    return InfoCard(
      title: 'Last Result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: image.width / image.height,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: mediaPrimaryPreview(image, fit: BoxFit.cover),
                ),
                if (image.canPreviewFile)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: MediaFullscreenButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<String>(
                            builder: (context) => FullscreenMediaPage(
                              images: [image],
                              initialIndex: 0,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton.outlined(
                onPressed: image.isPending ? null : deleteLatestResult,
                style: IconButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                tooltip: isStored ? 'Delete' : 'Discard',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            image.finalPositivePrompt,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
