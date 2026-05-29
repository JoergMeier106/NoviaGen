import 'package:flutter/material.dart';

import 'package:noviagen/media_video_player.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/shared/cached_media_image.dart';

Widget mediaPreviewPoster(ImageRecord media, {BoxFit fit = BoxFit.cover}) {
  if (media.isPending) {
    return pendingMediaPlaceholder(fit: fit);
  }
  final preferVideoPoster =
      media.isVideo && (fit == BoxFit.contain || fit == BoxFit.scaleDown);
  final previewUrl = preferVideoPoster
      ? media.posterUrl ?? media.thumbnailUrl ?? media.previewUrl
      : media.thumbnailUrl ?? media.posterUrl ?? media.previewUrl;
  if (previewUrl.isEmpty) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black12),
      child: Center(child: Icon(Icons.broken_image_outlined, size: 32)),
    );
  }

  return CachedMediaImage(
    key: ValueKey('media-poster-$previewUrl'),
    imageUrl: previewUrl,
    fit: fit,
    memCacheWidth: 420,
    memCacheHeight: 420,
    maxWidthDiskCache: 420,
    maxHeightDiskCache: 420,
    placeholderBuilder: (context) =>
        const Center(child: CircularProgressIndicator()),
    errorBuilder: (context) => const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black12),
      child: Center(child: Icon(Icons.broken_image_outlined, size: 32)),
    ),
  );
}

Widget pendingMediaPlaceholder({BoxFit fit = BoxFit.cover}) {
  return DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF5A616B), Color(0xFF3F464E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        ),
      ),
    ),
  );
}

Widget mediaPrimaryPreview(
  ImageRecord media, {
  BoxFit fit = BoxFit.cover,
  bool autoplayVideo = false,
  bool showVideoControls = true,
}) {
  if (!media.canPreviewFile) {
    return mediaPreviewPoster(media, fit: fit);
  }
  if (media.isVideo) {
    return MediaVideoPlayer(
      url: media.fileUrl,
      poster: mediaPreviewPoster(media, fit: fit),
      autoplay: autoplayVideo,
      fit: fit,
      showControls: showVideoControls,
    );
  }
  return InteractiveViewer(
    minScale: 1,
    maxScale: 5,
    child: CachedMediaImage(
      key: ValueKey('media-image-${media.fileUrl}'),
      imageUrl: media.fileUrl,
      fit: fit,
      placeholderBuilder: (context) =>
          const Center(child: CircularProgressIndicator()),
      errorBuilder: (context) =>
          const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
    ),
  );
}
