import 'package:flutter_app/models/media.dart';
enum GallerySortOption {
  newest,
  oldest,
  ratingHigh,
  ratingLow,
  resolutionHigh,
  durationHigh,
  durationLow,
  generationDurationHigh,
  generationDurationLow,
}

enum GalleryMediaTypeFilter { all, images, gifs, videos }

enum GalleryGroupOption { none, model, rating, mediaType }

class GalleryGroupSection {
  GalleryGroupSection({required this.title, required this.items});

  final String title;
  final List<ImageRecord> items;
}

class GalleryQuery {
  const GalleryQuery({
    required this.search,
    required this.model,
    required this.includeTags,
    required this.excludeTags,
    required this.minRating,
    required this.mediaType,
    required this.showDeleted,
    required this.showPlaceholders,
  });

  final String search;
  final String? model;
  final List<String> includeTags;
  final List<String> excludeTags;
  final int minRating;
  final GalleryMediaTypeFilter mediaType;
  final bool showDeleted;
  final bool showPlaceholders;
}
