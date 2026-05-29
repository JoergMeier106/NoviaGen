import 'package:flutter/material.dart';

import 'package:noviagen/models/media.dart';
import 'package:noviagen/shared/app_formatters.dart';
import 'package:noviagen/shared/media_preview.dart';
import 'package:noviagen/shared/widgets/common_widgets.dart';


class GalleryListRow {
  const GalleryListRow.header({
    required this.title,
    required this.count,
    required this.expanded,
  }) : image = null;

  const GalleryListRow.image(this.image)
    : title = null,
      count = null,
      expanded = false;

  final String? title;
  final int? count;
  final bool expanded;
  final ImageRecord? image;

  bool get isHeader => title != null;
}

class GalleryImageTile extends StatefulWidget {
  const GalleryImageTile({
    super.key,
    required this.image,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
    this.onLongPress,
  });

  final ImageRecord image;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback? onLongPress;

  @override
  State<GalleryImageTile> createState() => GalleryImageTileState();
}

class GalleryImageTileState extends State<GalleryImageTile> {
  static const double _previewSize = 140;
  static const double _tilePadding = 12;
  static const double _chevronVisualSize = 24;
  static const double _chevronHitSize = 48;

  final GlobalKey _tileInkKey = GlobalKey();

  bool _expanded = false;
  bool _lastTapWasChevronHit = false;

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  void _handleTileTapUp(TapUpDetails details) {
    _lastTapWasChevronHit = _isInChevronHitArea(details.localPosition);
    if (_lastTapWasChevronHit) {
      _toggleExpanded();
    }
  }

  void _handleTileTap() {
    if (_lastTapWasChevronHit) {
      _lastTapWasChevronHit = false;
      return;
    }
    if (widget.selectionMode) {
      widget.onSelectionChanged?.call(!widget.selected);
      return;
    }
    widget.onTap();
  }

  void _handleTileTapCancel() {
    _lastTapWasChevronHit = false;
  }

  bool _isInChevronHitArea(Offset position) {
    final renderObject = _tileInkKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final size = renderObject.size;
    final chevronCenterX = size.width - _tilePadding - (_chevronVisualSize / 2);
    final chevronCenterY = _expanded
        ? _tilePadding + _previewSize + 10 + (_chevronVisualSize / 2)
        : size.height - _tilePadding - (_chevronVisualSize / 2);
    final hitRect = Rect.fromCenter(
      center: Offset(chevronCenterX, chevronCenterY),
      width: _chevronHitSize,
      height: _chevronHitSize,
    ).intersect(Offset.zero & size);

    return hitRect.contains(position);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final promptText = image.prompt.isEmpty
        ? image.finalPositivePrompt
        : image.prompt;
    final isImageToVideo =
        image.isVideo &&
        (image.sourceImageId != null ||
            image.modelId.toLowerCase().contains('image') ||
            image.prompt.toLowerCase().contains('image to video'));
    final mediaTypeChip = MetaChip(
      icon: image.isVideo
          ? Icons.videocam
          : image.isGif
          ? Icons.gif_box_outlined
          : Icons.image_outlined,
      label: image.mediaTypeLabel,
    );
    final resolutionChip = MetaChip(label: '${image.width} x ${image.height}');
    final ratingChip = MetaChip(icon: Icons.star, label: '${image.rating}/5');
    final deletedChip = MetaChip(icon: Icons.delete_outline, label: 'Deleted');
    final leftColumnChips = <Widget>[
      mediaTypeChip,
      resolutionChip,
      if (image.generationDurationSeconds != null &&
          image.generationDurationSeconds! > 0)
        MetaChip(
          icon: Icons.bolt_outlined,
          label:
              'Gen ${formatGenerationDurationLabel(image.generationDurationSeconds)}',
        ),
      if (image.durationSeconds != null)
        MetaChip(
          icon: image.isVideo ? Icons.timer_outlined : Icons.schedule,
          label: image.isVideo
              ? 'Playback ${formatDurationLabel(image.durationSeconds)}'
              : 'Duration ${formatDurationLabel(image.durationSeconds)}',
        ),
      if (image.isVideo && image.fps != null)
        MetaChip(label: '${image.fps} FPS'),
    ];

    final rightColumnChips = <Widget>[
      if (image.isDeleted) deletedChip,
      MetaChip(label: image.modelId),
      ratingChip,
      MetaChip(
        icon: Icons.schedule_outlined,
        label: formatTimestamp(image.createdAt),
      ),
      if (image.isVideo)
        MetaChip(
          icon: Icons.movie_filter_outlined,
          label: isImageToVideo ? 'Image to video' : 'Text to video',
        ),
      if (image.isGif)
        MetaChip(
          icon: Icons.movie_filter_outlined,
          label: image.sourceImageId != null ? 'Video to GIF' : 'GIF',
        ),
      ...image.tags
          .take(4)
          .map((tag) => MetaChip(icon: Icons.sell_outlined, label: tag)),
      if (image.tags.length > 4)
        MetaChip(label: '+${image.tags.length - 4} tags'),
    ];
    final summaryChips = <Widget>[mediaTypeChip, resolutionChip, ratingChip];
    final chevronButton = Tooltip(
      message: _expanded ? 'Collapse details' : 'Show details',
      child: InkResponse(
        onTap: _toggleExpanded,
        radius: 16,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
          ),
        ),
      ),
    );

    Widget preview() {
      return AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              mediaPreviewPoster(image, fit: BoxFit.cover),
              if (widget.selectionMode)
                Positioned(
                  left: 6,
                  top: 6,
                  child: _GallerySelectionBadge(selected: widget.selected),
                ),
              if (image.isVideo && !image.isPending)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatDurationLabel(image.durationSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: widget.selected
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        key: _tileInkKey,
        onTap: _handleTileTap,
        onTapUp: _handleTileTapUp,
        onTapCancel: _handleTileTapCancel,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 140, child: preview()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 140,
                      child: GalleryDetailBlock(
                        title: 'Prompt',
                        text: promptText,
                        maxLines: 5,
                        emphasize: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_expanded)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        'Details',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              'Context',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          chevronButton,
                        ],
                      ),
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: summaryChips,
                      ),
                    ),
                    const SizedBox(width: 6),
                    chevronButton,
                  ],
                ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: leftColumnChips,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: rightColumnChips,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GallerySelectionBadge extends StatelessWidget {
  const _GallerySelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? scheme.primary : scheme.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          selected ? Icons.check : Icons.check_box_outline_blank,
          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          size: 18,
        ),
      ),
    );
  }
}

class GalleryDetailBlock extends StatelessWidget {
  const GalleryDetailBlock({
    super.key,
    required this.title,
    required this.text,
    required this.maxLines,
    this.emphasize = false,
  });

  final String title;
  final String text;
  final int maxLines;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: emphasize
              ? theme.textTheme.titleSmall
              : theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class GalleryToolbar extends StatelessWidget {
  const GalleryToolbar({
    super.key,
    required this.sortLabel,
    required this.filterLabel,
    required this.groupLabel,
    required this.onSortTap,
    required this.onFilterTap,
    required this.onGroupTap,
    this.selectionLabel,
    this.selectionIcon,
    this.onSelectTap,
    this.onClearTap,
  });

  final String sortLabel;
  final String filterLabel;
  final String groupLabel;
  final String? selectionLabel;
  final IconData? selectionIcon;
  final VoidCallback onSortTap;
  final VoidCallback onFilterTap;
  final VoidCallback onGroupTap;
  final VoidCallback? onSelectTap;
  final VoidCallback? onClearTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ToolbarButton(
            icon: Icons.swap_vert,
            label: 'Sort: $sortLabel',
            onTap: onSortTap,
          ),
          const SizedBox(width: 8),
          ToolbarButton(
            icon: Icons.filter_alt_outlined,
            label: 'Filter: $filterLabel',
            onTap: onFilterTap,
          ),
          const SizedBox(width: 8),
          ToolbarButton(
            icon: Icons.view_stream_outlined,
            label: 'Group: $groupLabel',
            onTap: onGroupTap,
          ),
          if (onSelectTap != null && selectionLabel != null) ...[
            const SizedBox(width: 8),
            ToolbarButton(
              icon: selectionIcon ?? Icons.checklist,
              label: selectionLabel!,
              onTap: onSelectTap!,
            ),
          ],
          if (onClearTap != null) ...[
            const SizedBox(width: 8),
            ToolbarButton(
              icon: Icons.restart_alt,
              label: 'Reset',
              onTap: onClearTap!,
            ),
          ],
        ],
      ),
    );
  }
}
