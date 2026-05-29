import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/gallery.dart';
import '../models/media.dart';
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

class GalleryBrowserState {
  GalleryBrowserState({
    required this.reloadFirstPage,
    required this.sortLoadedItems,
    required this.onChanged,
  });

  static const searchQueryKey = 'gallery_search_query';
  static const modelFilterKey = 'gallery_model_filter';
  static const includeTagsKey = 'gallery_include_tags';
  static const excludeTagsKey = 'gallery_exclude_tags';
  static const minRatingKey = 'gallery_min_rating';
  static const sortOptionKey = 'gallery_sort_option';
  static const mediaTypeFilterKey = 'gallery_media_type_filter';
  static const groupOptionKey = 'gallery_group_option';
  static const showDeletedKey = 'gallery_show_deleted';
  static const showPlaceholdersKey = 'gallery_show_placeholders';
  static const slideshowIntervalSecondsKey =
      'gallery_slideshow_interval_seconds';

  final Future<void> Function() reloadFirstPage;
  final void Function() sortLoadedItems;
  final void Function() onChanged;

  bool loadingFirstPage = false;
  bool loadingNextPage = false;
  List<String> filterModels = <String>[];
  List<String> filterTags = <String>[];
  String searchQuery = '';
  String? modelFilter;
  List<String> includeTags = <String>[];
  List<String> excludeTags = <String>[];
  int minRating = 0;
  GallerySortOption sortOption = GallerySortOption.newest;
  GalleryMediaTypeFilter mediaTypeFilter = GalleryMediaTypeFilter.all;
  GalleryGroupOption groupOption = GalleryGroupOption.none;
  bool showDeleted = false;
  bool showPlaceholders = true;
  int slideshowIntervalSeconds = 5;
  int currentPage = 0;
  int totalCount = 0;
  bool hasMore = false;

  bool get loading => loadingFirstPage || loadingNextPage;

  List<String> get modelFilters => <String>['All models', ...filterModels];

  List<String> get availableTags => List<String>.from(filterTags);

  GalleryQuery get query => GalleryQuery(
    search: searchQuery,
    model: modelFilter,
    includeTags: includeTags,
    excludeTags: excludeTags,
    minRating: minRating,
    mediaType: mediaTypeFilter,
    showDeleted: showDeleted,
    showPlaceholders: showPlaceholders,
  );

  String get mediaTypeQueryValue => galleryMediaTypeQueryValue(mediaTypeFilter);

  List<GalleryGroupSection> groupItems(List<ImageRecord> items) {
    return groupGalleryItems(items, groupOption);
  }

  void loadPreferences(SharedPreferences prefs) {
    searchQuery = prefs.getString(searchQueryKey) ?? '';
    modelFilter = prefs.getString(modelFilterKey);
    includeTags = _normalizeTagSelection(
      prefs.getStringList(includeTagsKey) ?? const <String>[],
    );
    excludeTags = _normalizeTagSelection(
      prefs.getStringList(excludeTagsKey) ?? const <String>[],
    );
    minRating = prefs.getInt(minRatingKey) ?? 0;
    sortOption = _gallerySortOptionFromString(prefs.getString(sortOptionKey));
    mediaTypeFilter = _galleryMediaTypeFilterFromString(
      prefs.getString(mediaTypeFilterKey),
    );
    groupOption = _galleryGroupOptionFromString(
      prefs.getString(groupOptionKey),
    );
    showDeleted = prefs.getBool(showDeletedKey) ?? false;
    showPlaceholders = prefs.getBool(showPlaceholdersKey) ?? true;
    slideshowIntervalSeconds = prefs.getInt(slideshowIntervalSecondsKey) ?? 5;
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(searchQueryKey, searchQuery);
    if (modelFilter == null ||
        modelFilter!.isEmpty ||
        modelFilter == 'All models') {
      await prefs.remove(modelFilterKey);
    } else {
      await prefs.setString(modelFilterKey, modelFilter!);
    }
    await prefs.setStringList(includeTagsKey, includeTags);
    await prefs.setStringList(excludeTagsKey, excludeTags);
    await prefs.setInt(minRatingKey, minRating);
    await prefs.setString(sortOptionKey, sortOption.name);
    await prefs.setString(mediaTypeFilterKey, mediaTypeFilter.name);
    await prefs.setString(groupOptionKey, groupOption.name);
    await prefs.setBool(showDeletedKey, showDeleted);
    await prefs.setBool(showPlaceholdersKey, showPlaceholders);
    await prefs.setInt(slideshowIntervalSecondsKey, slideshowIntervalSeconds);
  }

  void resetPaging() {
    currentPage = 0;
    totalCount = 0;
    hasMore = false;
  }

  void updatePage(GalleryPageResponse page) {
    currentPage = page.page;
    totalCount = page.total;
    hasMore = page.hasMore;
  }

  void updateFilters(GalleryFiltersResponse filters) {
    filterModels = filters.models;
    filterTags = filters.tags;
  }

  void decrementTotalCount(int count) {
    totalCount = totalCount - count;
    if (totalCount < 0) {
      totalCount = 0;
    }
  }

  void incrementTotalCount() {
    totalCount += 1;
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    _persistReloadAndNotify();
  }

  void setModelFilter(String? value) {
    modelFilter = value;
    _persistReloadAndNotify();
  }

  void setIncludeTags(List<String> values) {
    includeTags = _normalizeTagSelection(values);
    _persistReloadAndNotify();
  }

  void setExcludeTags(List<String> values) {
    excludeTags = _normalizeTagSelection(values);
    _persistReloadAndNotify();
  }

  void setMinRating(int value) {
    minRating = value;
    _persistReloadAndNotify();
  }

  void setSortOption(GallerySortOption value) {
    sortOption = value;
    sortLoadedItems();
    _persistReloadAndNotify();
  }

  void setMediaTypeFilter(GalleryMediaTypeFilter value) {
    mediaTypeFilter = value;
    _persistReloadAndNotify();
  }

  void setGroupOption(GalleryGroupOption value) {
    groupOption = value;
    unawaited(savePreferences());
    onChanged();
  }

  void setShowDeleted(bool value) {
    showDeleted = value;
    _persistReloadAndNotify();
  }

  void setShowPlaceholders(bool value) {
    showPlaceholders = value;
    _persistReloadAndNotify();
  }

  void resetPreferences() {
    searchQuery = '';
    modelFilter = 'All models';
    includeTags = <String>[];
    excludeTags = <String>[];
    minRating = 0;
    sortOption = GallerySortOption.newest;
    mediaTypeFilter = GalleryMediaTypeFilter.all;
    groupOption = GalleryGroupOption.none;
    showDeleted = false;
    showPlaceholders = true;
    _persistReloadAndNotify();
  }

  void removeTagFromFilters(String normalizedTag) {
    includeTags = includeTags
        .where((value) => value.toLowerCase() != normalizedTag)
        .toList();
    excludeTags = excludeTags
        .where((value) => value.toLowerCase() != normalizedTag)
        .toList();
  }

  int compareItems(ImageRecord left, ImageRecord right) {
    return compareGalleryItems(left, right, sortOption);
  }

  bool matches(ImageRecord item) => matchesGalleryQuery(item, query);

  void _persistReloadAndNotify() {
    unawaited(savePreferences());
    unawaited(reloadFirstPage());
    onChanged();
  }
}

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

GallerySortOption _gallerySortOptionFromString(String? value) {
  for (final option in GallerySortOption.values) {
    if (option.name == value) {
      return option;
    }
  }
  return GallerySortOption.newest;
}

GalleryMediaTypeFilter _galleryMediaTypeFilterFromString(String? value) {
  for (final option in GalleryMediaTypeFilter.values) {
    if (option.name == value) {
      return option;
    }
  }
  return GalleryMediaTypeFilter.all;
}

GalleryGroupOption _galleryGroupOptionFromString(String? value) {
  for (final option in GalleryGroupOption.values) {
    if (option.name == value) {
      return option;
    }
  }
  return GalleryGroupOption.none;
}

List<String> _normalizeTagSelection(List<String> tags) {
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
