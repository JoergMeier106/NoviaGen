import 'dart:async';

import 'package:flutter/material.dart';

import 'package:noviagen/media_video_player.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/shared/cached_media_image.dart';
import 'package:noviagen/shared/media_preview.dart';
import 'package:noviagen/features/gallery/fullscreen_controls.dart';

class FullscreenTopOverlay extends StatelessWidget {
  const FullscreenTopOverlay({
    super.key,
    required this.topPadding,
    required this.counterLabel,
    required this.showCounter,
    required this.showSourcePreview,
    required this.canStartSlideshow,
    required this.slideshowRunning,
    required this.onToggleSlideshow,
    required this.onClose,
  });

  final double topPadding;
  final String counterLabel;
  final bool showCounter;
  final bool showSourcePreview;
  final bool canStartSlideshow;
  final bool slideshowRunning;
  final VoidCallback onToggleSlideshow;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: topPadding + 16,
      left: 16,
      right: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showCounter)
            FullscreenStatusChip(
              icon: Icons.photo_library_outlined,
              label: counterLabel,
            ),
          if (showSourcePreview) ...[
            const SizedBox(width: 10),
            const FullscreenStatusChip(
              icon: Icons.compare,
              label: 'Source preview',
            ),
          ],
          const Spacer(),
          if (canStartSlideshow) ...[
            FullscreenIconActionButton(
              icon: slideshowRunning ? Icons.pause : Icons.play_arrow,
              tooltip: slideshowRunning ? 'Stop slideshow' : 'Start slideshow',
              onTap: onToggleSlideshow,
            ),
            const SizedBox(width: 10),
          ],
          FullscreenIconActionButton(
            icon: Icons.close,
            tooltip: 'Close',
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class FullscreenSourcePreviewOverlay extends StatelessWidget {
  const FullscreenSourcePreviewOverlay({
    super.key,
    required this.currentImage,
    required this.viewportSize,
    required this.viewPadding,
    required this.interfaceVisible,
    required this.showingSourcePreview,
    required this.onPressedStateChanged,
  });

  final ImageRecord currentImage;
  final Size viewportSize;
  final EdgeInsets viewPadding;
  final bool interfaceVisible;
  final bool showingSourcePreview;
  final FutureOr<void> Function(bool) onPressedStateChanged;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: _bottomOffset,
      child: Center(
        child: FullscreenHoldActionButton(
          icon: Icons.compare,
          label: showingSourcePreview ? 'Showing source' : 'Hold for source',
          onPressedStateChanged: onPressedStateChanged,
        ),
      ),
    );
  }

  double get _bottomOffset {
    const overlayBottomMargin = 20.0;
    const videoControlsBottomInset = 8.0;
    const videoControlsHeight = 64.0;
    const mediaToOverlayGap = 12.0;
    final minimumBottomOffset = viewPadding.bottom + overlayBottomMargin;
    if (!interfaceVisible) {
      return minimumBottomOffset;
    }
    final mediaRect = _mediaRect;
    final letterboxBottom = viewportSize.height - mediaRect.bottom;
    final mediaBottomInset = letterboxBottom > 0 ? letterboxBottom : 0.0;
    final overlayAboveControls =
        mediaBottomInset +
        videoControlsBottomInset +
        videoControlsHeight +
        mediaToOverlayGap;
    return overlayAboveControls > minimumBottomOffset
        ? overlayAboveControls
        : minimumBottomOffset;
  }

  Rect get _mediaRect {
    final viewportWidth = viewportSize.width > 0 ? viewportSize.width : 1.0;
    final viewportHeight = viewportSize.height > 0 ? viewportSize.height : 1.0;
    final mediaWidth = currentImage.width > 0
        ? currentImage.width.toDouble()
        : 1.0;
    final mediaHeight = currentImage.height > 0
        ? currentImage.height.toDouble()
        : 1.0;
    final fittedSizes = applyBoxFit(
      BoxFit.contain,
      Size(mediaWidth, mediaHeight),
      Size(viewportWidth, viewportHeight),
    );
    final destinationSize = fittedSizes.destination;
    return Rect.fromLTWH(
      (viewportWidth - destinationSize.width) / 2,
      (viewportHeight - destinationSize.height) / 2,
      destinationSize.width,
      destinationSize.height,
    );
  }
}

class FullscreenMediaFrame extends StatelessWidget {
  const FullscreenMediaFrame({
    super.key,
    required this.image,
    required this.showControls,
    required this.initiallyMuted,
    required this.autoplay,
    required this.interactiveZoom,
    required this.transformationController,
    required this.playbackController,
    required this.onToggleInterface,
    required this.onDoubleTapDown,
    required this.onDoubleTap,
    required this.onInteractionEnd,
  });

  final ImageRecord image;
  final bool showControls;
  final bool initiallyMuted;
  final bool autoplay;
  final bool interactiveZoom;
  final TransformationController? transformationController;
  final MediaVideoPlaybackController? playbackController;
  final VoidCallback onToggleInterface;
  final GestureTapDownCallback onDoubleTapDown;
  final VoidCallback onDoubleTap;
  final GestureScaleEndCallback? onInteractionEnd;

  @override
  Widget build(BuildContext context) {
    if (!image.canPreviewFile) {
      return _PendingFullscreenMedia(
        image: image,
        onToggleInterface: onToggleInterface,
      );
    }
    return image.isVideo ? _buildVideoFrame() : _buildImageFrame();
  }

  Widget _buildVideoFrame() {
    return Center(
      child: AspectRatio(
        aspectRatio: image.width / image.height,
        child: MediaVideoPlayer(
          url: image.fileUrl,
          poster: mediaPreviewPoster(image, fit: BoxFit.contain),
          autoplay: autoplay,
          fit: BoxFit.contain,
          showControls: showControls,
          initiallyMuted: initiallyMuted,
          playbackController: playbackController,
          onSurfaceTap: onToggleInterface,
          onDoubleTapDown: onDoubleTapDown,
          onDoubleTap: onDoubleTap,
          transformationController: transformationController,
          interactiveGesturesEnabled: interactiveZoom,
          minScale: 1,
          maxScale: 6,
          onInteractionEnd: onInteractionEnd,
        ),
      ),
    );
  }

  Widget _buildImageFrame() {
    return Center(
      child: AspectRatio(
        aspectRatio: image.width / image.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggleInterface,
          onDoubleTapDown: onDoubleTapDown,
          onDoubleTap: onDoubleTap,
          child: InteractiveViewer(
            transformationController: transformationController,
            panEnabled: interactiveZoom,
            scaleEnabled: interactiveZoom,
            minScale: 1,
            maxScale: 6,
            onInteractionEnd: onInteractionEnd,
            child: Center(
              child: CachedMediaImage(
                imageUrl: image.fileUrl,
                fit: BoxFit.contain,
                placeholderBuilder: (context) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (context) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingFullscreenMedia extends StatelessWidget {
  const _PendingFullscreenMedia({
    required this.image,
    required this.onToggleInterface,
  });

  final ImageRecord image;
  final VoidCallback onToggleInterface;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleInterface,
      child: Center(
        child: AspectRatio(
          aspectRatio: image.width / image.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [pendingMediaPlaceholder(fit: BoxFit.contain)],
            ),
          ),
        ),
      ),
    );
  }
}
