import 'package:flutter/material.dart';

import 'package:noviagen/features/gallery/domain/gallery_selection_capabilities.dart';

class GallerySelectionActionBarHeader extends SliverPersistentHeaderDelegate {
  const GallerySelectionActionBarHeader({
    required this.selectedCount,
    required this.capabilities,
    required this.onClearSelection,
    required this.onDownload,
    required this.onRegenerate,
    required this.onScale,
    required this.onGenerateAudioVideo,
    required this.onConvertToGif,
    required this.onUseAsImageSource,
    required this.onCreateVideo,
    required this.onCreatePromptAndVideo,
    required this.onRestore,
    required this.onDelete,
    required this.onCancelJobs,
  });

  final int selectedCount;
  final GallerySelectionCapabilities capabilities;
  final VoidCallback onClearSelection;
  final VoidCallback? onDownload;
  final VoidCallback? onRegenerate;
  final VoidCallback? onScale;
  final VoidCallback? onGenerateAudioVideo;
  final VoidCallback? onConvertToGif;
  final VoidCallback? onUseAsImageSource;
  final VoidCallback? onCreateVideo;
  final VoidCallback? onCreatePromptAndVideo;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final VoidCallback? onCancelJobs;

  @override
  double get minExtent => GallerySelectionActionBar.headerHeight;

  @override
  double get maxExtent => GallerySelectionActionBar.headerHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: GallerySelectionActionBar(
          selectedCount: selectedCount,
          capabilities: capabilities,
          onClearSelection: onClearSelection,
          onDownload: onDownload,
          onRegenerate: onRegenerate,
          onScale: onScale,
          onGenerateAudioVideo: onGenerateAudioVideo,
          onConvertToGif: onConvertToGif,
          onUseAsImageSource: onUseAsImageSource,
          onCreateVideo: onCreateVideo,
          onCreatePromptAndVideo: onCreatePromptAndVideo,
          onRestore: onRestore,
          onDelete: onDelete,
          onCancelJobs: onCancelJobs,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant GallerySelectionActionBarHeader oldDelegate) {
    return selectedCount != oldDelegate.selectedCount ||
        capabilities != oldDelegate.capabilities ||
        onClearSelection != oldDelegate.onClearSelection ||
        onDownload != oldDelegate.onDownload ||
        onRegenerate != oldDelegate.onRegenerate ||
        onScale != oldDelegate.onScale ||
        onGenerateAudioVideo != oldDelegate.onGenerateAudioVideo ||
        onConvertToGif != oldDelegate.onConvertToGif ||
        onUseAsImageSource != oldDelegate.onUseAsImageSource ||
        onCreateVideo != oldDelegate.onCreateVideo ||
        onCreatePromptAndVideo != oldDelegate.onCreatePromptAndVideo ||
        onRestore != oldDelegate.onRestore ||
        onDelete != oldDelegate.onDelete ||
        onCancelJobs != oldDelegate.onCancelJobs;
  }
}

class GallerySelectionActionBar extends StatelessWidget {
  const GallerySelectionActionBar({
    super.key,
    required this.selectedCount,
    required this.capabilities,
    required this.onClearSelection,
    required this.onDownload,
    required this.onRegenerate,
    required this.onScale,
    required this.onGenerateAudioVideo,
    required this.onConvertToGif,
    required this.onUseAsImageSource,
    required this.onCreateVideo,
    required this.onCreatePromptAndVideo,
    required this.onRestore,
    required this.onDelete,
    required this.onCancelJobs,
  });

  static const double headerHeight = 72;

  final int selectedCount;
  final GallerySelectionCapabilities capabilities;
  final VoidCallback onClearSelection;
  final VoidCallback? onDownload;
  final VoidCallback? onRegenerate;
  final VoidCallback? onScale;
  final VoidCallback? onGenerateAudioVideo;
  final VoidCallback? onConvertToGif;
  final VoidCallback? onUseAsImageSource;
  final VoidCallback? onCreateVideo;
  final VoidCallback? onCreatePromptAndVideo;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final VoidCallback? onCancelJobs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionButtons = _actionButtons(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              selectedCount == 1 ? '1 selected' : '$selectedCount selected',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: selectedCount == 0
                  ? Text(
                      'Select media entries',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    )
                  : !capabilities.hasAnyAction || actionButtons.isEmpty
                  ? Text(
                      'No shared actions',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: actionButtons),
                    ),
            ),
            IconButton(
              onPressed: onClearSelection,
              icon: const Icon(Icons.close),
              tooltip: 'Clear selection',
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actionButtons(BuildContext context) {
    final buttons = <Widget>[
      if (onDownload != null)
        _GallerySelectionIconButton(
          icon: Icons.download,
          tooltip: 'Download',
          onPressed: onDownload,
          prominence: _GallerySelectionButtonProminence.filled,
        ),
      if (onRegenerate != null)
        _GallerySelectionIconButton(
          icon: Icons.refresh,
          tooltip: 'Regenerate',
          onPressed: onRegenerate,
          prominence: _GallerySelectionButtonProminence.filledTonal,
        ),
      if (onScale != null)
        _GallerySelectionIconButton(
          icon: Icons.zoom_out_map,
          tooltip: 'Scale',
          onPressed: onScale,
        ),
      if (onGenerateAudioVideo != null)
        _GallerySelectionIconButton(
          icon: Icons.music_video_outlined,
          tooltip: 'Generate with audio',
          onPressed: onGenerateAudioVideo,
        ),
      if (onConvertToGif != null)
        _GallerySelectionIconButton(
          icon: Icons.transform,
          tooltip: 'Convert to GIF',
          onPressed: onConvertToGif,
        ),
      if (onUseAsImageSource != null)
        _GallerySelectionIconButton(
          icon: Icons.auto_awesome,
          tooltip: 'Use as image source',
          onPressed: onUseAsImageSource,
        ),
      if (onCreateVideo != null)
        _GallerySelectionIconButton(
          icon: Icons.movie_creation_outlined,
          tooltip: 'Create video',
          onPressed: onCreateVideo,
        ),
      if (onCreatePromptAndVideo != null)
        _GallerySelectionIconButton(
          icon: Icons.auto_awesome_motion_outlined,
          tooltip: 'Create prompt and video',
          onPressed: onCreatePromptAndVideo,
        ),
      if (onRestore != null)
        _GallerySelectionIconButton(
          icon: Icons.settings_backup_restore_outlined,
          tooltip: 'Restore',
          onPressed: onRestore,
          prominence: _GallerySelectionButtonProminence.filledTonal,
        ),
      if (onDelete != null)
        _GallerySelectionIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete',
          onPressed: onDelete,
          destructive: true,
          prominence: _GallerySelectionButtonProminence.filledTonal,
        ),
      if (onCancelJobs != null)
        _GallerySelectionIconButton(
          icon: Icons.cancel_outlined,
          tooltip: 'Cancel jobs',
          onPressed: onCancelJobs,
          destructive: true,
          prominence: _GallerySelectionButtonProminence.filledTonal,
        ),
    ];

    if (buttons.isEmpty) {
      return buttons;
    }

    return [
      for (var index = 0; index < buttons.length; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        buttons[index],
      ],
    ];
  }
}

enum _GallerySelectionButtonProminence { filled, filledTonal, outlined }

class _GallerySelectionIconButton extends StatelessWidget {
  const _GallerySelectionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
    this.prominence = _GallerySelectionButtonProminence.outlined,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;
  final _GallerySelectionButtonProminence prominence;

  @override
  Widget build(BuildContext context) {
    final iconColor = destructive ? Theme.of(context).colorScheme.error : null;
    final buttonIcon = Icon(icon);
    final style = iconColor == null
        ? null
        : IconButton.styleFrom(foregroundColor: iconColor);

    switch (prominence) {
      case _GallerySelectionButtonProminence.filled:
        return IconButton.filled(
          onPressed: onPressed,
          icon: buttonIcon,
          tooltip: tooltip,
          style: style,
        );
      case _GallerySelectionButtonProminence.filledTonal:
        return IconButton.filledTonal(
          onPressed: onPressed,
          icon: buttonIcon,
          tooltip: tooltip,
          style: style,
        );
      case _GallerySelectionButtonProminence.outlined:
        return IconButton.outlined(
          onPressed: onPressed,
          icon: buttonIcon,
          tooltip: tooltip,
          style: style,
        );
    }
  }
}
