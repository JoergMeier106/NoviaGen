import 'package:noviagen/features/gallery/domain/gallery_query.dart';
import 'package:noviagen/models/media.dart';
String galleryMediaTypeQueryValue(GalleryMediaTypeFilter value) {
  switch (value) {
    case GalleryMediaTypeFilter.all:
      return 'all';
    case GalleryMediaTypeFilter.images:
      return 'images';
    case GalleryMediaTypeFilter.gifs:
      return 'gifs';
    case GalleryMediaTypeFilter.videos:
      return 'videos';
  }
}

bool matchesGalleryQuery(ImageRecord item, GalleryQuery query) {
  final search = query.search.trim().toLowerCase();
  final matchesSearch =
      search.isEmpty ||
      item.prompt.toLowerCase().contains(search) ||
      item.finalPositivePrompt.toLowerCase().contains(search) ||
      item.modelId.toLowerCase().contains(search);
  final matchesModel =
      query.model == null ||
      query.model == 'All models' ||
      item.modelId == query.model;
  final normalizedItemTags = item.tags.map((tag) => tag.toLowerCase()).toSet();
  final matchesIncludedTags = query.includeTags.every(
    (tag) => normalizedItemTags.contains(tag.toLowerCase()),
  );
  final matchesExcludedTags = query.excludeTags.every(
    (tag) => !normalizedItemTags.contains(tag.toLowerCase()),
  );
  final matchesRating = item.rating >= query.minRating;
  final matchesMediaType = switch (query.mediaType) {
    GalleryMediaTypeFilter.all => true,
    GalleryMediaTypeFilter.images => item.isImage,
    GalleryMediaTypeFilter.gifs => item.isGif,
    GalleryMediaTypeFilter.videos => item.isVideo,
  };
  final matchesDeletedState = query.showDeleted
      ? item.isDeleted
      : !item.isDeleted;
  final matchesPlaceholderState = query.showPlaceholders || !item.isPending;
  return matchesSearch &&
      matchesModel &&
      matchesIncludedTags &&
      matchesExcludedTags &&
      matchesRating &&
      matchesMediaType &&
      matchesDeletedState &&
      matchesPlaceholderState;
}

int compareGalleryItems(
  ImageRecord left,
  ImageRecord right,
  GallerySortOption sortOption,
) {
  double runtimeOf(ImageRecord item) => item.durationSeconds ?? 0;
  double generationRuntimeOf(ImageRecord item) =>
      item.generationDurationSeconds ?? 0;

  switch (sortOption) {
    case GallerySortOption.oldest:
      return left.createdAt.compareTo(right.createdAt);
    case GallerySortOption.ratingHigh:
      final ratingCompare = right.rating.compareTo(left.rating);
      return ratingCompare != 0
          ? ratingCompare
          : right.createdAt.compareTo(left.createdAt);
    case GallerySortOption.ratingLow:
      final ratingCompare = left.rating.compareTo(right.rating);
      return ratingCompare != 0
          ? ratingCompare
          : right.createdAt.compareTo(left.createdAt);
    case GallerySortOption.resolutionHigh:
      final areaCompare = (right.width * right.height).compareTo(
        left.width * left.height,
      );
      return areaCompare != 0
          ? areaCompare
          : right.createdAt.compareTo(left.createdAt);
    case GallerySortOption.durationHigh:
      final durationCompare = runtimeOf(right).compareTo(runtimeOf(left));
      return durationCompare != 0
          ? durationCompare
          : right.createdAt.compareTo(left.createdAt);
    case GallerySortOption.durationLow:
      final durationCompare = runtimeOf(left).compareTo(runtimeOf(right));
      return durationCompare != 0
          ? durationCompare
          : right.createdAt.compareTo(left.createdAt);
    case GallerySortOption.generationDurationHigh:
      final durationCompare = generationRuntimeOf(
        right,
      ).compareTo(generationRuntimeOf(left));
      return durationCompare != 0
          ? durationCompare
          : right.createdAt.compareTo(left.createdAt);
    case GallerySortOption.generationDurationLow:
      final durationCompare = generationRuntimeOf(
        left,
      ).compareTo(generationRuntimeOf(right));
      return durationCompare != 0
          ? durationCompare
          : right.createdAt.compareTo(left.createdAt);
    case GallerySortOption.newest:
      return right.createdAt.compareTo(left.createdAt);
  }
}

List<GalleryGroupSection> groupGalleryItems(
  List<ImageRecord> items,
  GalleryGroupOption option,
) {
  if (option == GalleryGroupOption.none) {
    return [GalleryGroupSection(title: '', items: items)];
  }

  final groups = <String, List<ImageRecord>>{};
  for (final item in items) {
    final key = switch (option) {
      GalleryGroupOption.model => item.modelId,
      GalleryGroupOption.rating => '${item.rating} stars',
      GalleryGroupOption.mediaType =>
        item.isVideo
            ? 'Videos'
            : item.isGif
            ? 'GIFs'
            : 'Images',
      GalleryGroupOption.none => '',
    };
    groups.putIfAbsent(key, () => <ImageRecord>[]).add(item);
  }

  return groups.entries
      .map((entry) => GalleryGroupSection(title: entry.key, items: entry.value))
      .toList();
}

GallerySortOption gallerySortOptionFromString(String? value) {
  for (final option in GallerySortOption.values) {
    if (option.name == value) {
      return option;
    }
  }
  return GallerySortOption.newest;
}

GalleryMediaTypeFilter galleryMediaTypeFilterFromString(String? value) {
  for (final option in GalleryMediaTypeFilter.values) {
    if (option.name == value) {
      return option;
    }
  }
  return GalleryMediaTypeFilter.all;
}

GalleryGroupOption galleryGroupOptionFromString(String? value) {
  for (final option in GalleryGroupOption.values) {
    if (option.name == value) {
      return option;
    }
  }
  return GalleryGroupOption.none;
}

List<String> normalizeGalleryTagSelection(List<String> tags) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final raw in tags) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final lowered = trimmed.toLowerCase();
    if (seen.add(lowered)) {
      normalized.add(trimmed);
    }
  }
  normalized.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );
  return normalized;
}
