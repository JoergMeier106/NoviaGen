import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_app/shared/media_image_errors.dart';

class CachedMediaImage extends StatelessWidget {
  const CachedMediaImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  static final Set<String> _pendingEvictions = <String>{};

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      maxWidthDiskCache: maxWidthDiskCache,
      maxHeightDiskCache: maxHeightDiskCache,
      placeholder: (context, _) =>
          placeholderBuilder?.call(context) ?? const SizedBox.shrink(),
      errorListener: _handleLoadError,
      errorWidget: (context, _, error) {
        _handleLoadError(error);
        return errorBuilder?.call(context) ??
            const Center(child: Icon(Icons.broken_image_outlined, size: 32));
      },
    );
  }

  void _handleLoadError(Object error) {
    if (!isRecoverableCachedImageLoadError(error) ||
        !_pendingEvictions.add(imageUrl)) {
      return;
    }
    scheduleMicrotask(() async {
      try {
        await CachedNetworkImage.evictFromCache(imageUrl);
        final resizedCacheKey = _resizedCacheKey;
        if (resizedCacheKey != null) {
          await CachedNetworkImage.evictFromCache(
            imageUrl,
            cacheKey: resizedCacheKey,
          );
        }
      } finally {
        _pendingEvictions.remove(imageUrl);
      }
    });
  }

  String? get _resizedCacheKey {
    if (maxWidthDiskCache == null && maxHeightDiskCache == null) {
      return null;
    }
    final buffer = StringBuffer('resized');
    if (maxWidthDiskCache != null) {
      buffer.write('_w$maxWidthDiskCache');
    }
    if (maxHeightDiskCache != null) {
      buffer.write('_h$maxHeightDiskCache');
    }
    buffer.write('_$imageUrl');
    return buffer.toString();
  }
}
