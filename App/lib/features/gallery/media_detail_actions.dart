import 'package:flutter/material.dart';

import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';

class MediaDetailActionBar extends StatelessWidget {
  const MediaDetailActionBar({
    super.key,
    required this.image,
    required this.currentJob,
    required this.onDownload,
    required this.onRegenerate,
    required this.onScale,
    required this.onGenerateAudioVideo,
    required this.onConvertToGif,
    required this.onCancelJob,
    required this.onUseAsImageSource,
    required this.onCreateVideo,
    required this.onCreatePromptAndVideo,
    required this.onRestore,
    required this.onDelete,
  });

  final ImageRecord image;
  final JobStatus? currentJob;
  final VoidCallback? onDownload;
  final VoidCallback? onRegenerate;
  final VoidCallback? onScale;
  final VoidCallback? onGenerateAudioVideo;
  final VoidCallback? onConvertToGif;
  final VoidCallback? onCancelJob;
  final VoidCallback onUseAsImageSource;
  final VoidCallback onCreateVideo;
  final VoidCallback? onCreatePromptAndVideo;
  final VoidCallback onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        IconButton.filled(
          onPressed: onDownload,
          icon: const Icon(Icons.download),
          tooltip: 'Download',
        ),
        if (image.canRegenerate)
          IconButton.filledTonal(
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh),
            tooltip: 'Regenerate',
          ),
        if (image.canScale)
          IconButton.outlined(
            onPressed: onScale,
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Scale',
          ),
        if (image.isVideo) ...[
          IconButton.outlined(
            onPressed: onGenerateAudioVideo,
            icon: const Icon(Icons.music_video_outlined),
            tooltip: 'Generate with audio',
          ),
          IconButton.outlined(
            onPressed: onConvertToGif,
            icon: const Icon(Icons.transform),
            tooltip: 'Convert to GIF',
          ),
        ],
        if (image.isStillImage) ...[
          IconButton.outlined(
            onPressed: onUseAsImageSource,
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Use as image source',
          ),
          IconButton.outlined(
            onPressed: onCreateVideo,
            icon: const Icon(Icons.movie_creation_outlined),
            tooltip: 'Create video',
          ),
          if (onCreatePromptAndVideo != null)
            IconButton.outlined(
              onPressed: onCreatePromptAndVideo,
              icon: const Icon(Icons.auto_awesome_motion_outlined),
              tooltip: 'Create prompt and video',
            ),
        ],
        if (image.isDeleted)
          IconButton.filledTonal(
            onPressed: onRestore,
            icon: const Icon(Icons.settings_backup_restore_outlined),
            tooltip: 'Restore',
          )
        else
          IconButton.filledTonal(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            color: Theme.of(context).colorScheme.error,
          ),
        if (_canCancelCurrentJob)
          IconButton.filledTonal(
            onPressed: onCancelJob,
            icon: const Icon(Icons.cancel_outlined),
            tooltip: 'Cancel job',
            color: Theme.of(context).colorScheme.error,
          ),
      ],
    );
  }

  bool get _canCancelCurrentJob {
    return image.isPending &&
        currentJob?.canCancel == true &&
        currentJob?.cancelRequested == false;
  }
}
