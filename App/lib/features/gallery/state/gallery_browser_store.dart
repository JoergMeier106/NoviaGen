import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/features/gallery/domain/gallery_filtering.dart';
import 'package:flutter_app/features/gallery/domain/gallery_query.dart';
import 'package:flutter_app/models/gallery.dart';
import 'package:flutter_app/models/media.dart';
export 'package:flutter_app/features/gallery/domain/gallery_filtering.dart';
export 'package:flutter_app/features/gallery/domain/gallery_query.dart';

class GalleryBrowserStore {
  GalleryBrowserStore({
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
    includeTags = normalizeGalleryTagSelection(
      prefs.getStringList(includeTagsKey) ?? const <String>[],
    );
    excludeTags = normalizeGalleryTagSelection(
      prefs.getStringList(excludeTagsKey) ?? const <String>[],
    );
    minRating = prefs.getInt(minRatingKey) ?? 0;
    sortOption = gallerySortOptionFromString(prefs.getString(sortOptionKey));
    mediaTypeFilter = galleryMediaTypeFilterFromString(
      prefs.getString(mediaTypeFilterKey),
    );
    groupOption = galleryGroupOptionFromString(
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
    includeTags = normalizeGalleryTagSelection(values);
    _persistReloadAndNotify();
  }

  void setExcludeTags(List<String> values) {
    excludeTags = normalizeGalleryTagSelection(values);
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
