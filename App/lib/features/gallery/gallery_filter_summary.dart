import 'package:flutter/material.dart';

import 'package:flutter_app/features/gallery/state/gallery_browser_store.dart';
import 'package:flutter_app/features/gallery/gallery_view_model.dart';
import 'package:flutter_app/shared/widgets/common_widgets.dart';


String gallerySortLabel(GallerySortOption option) {
  switch (option) {
    case GallerySortOption.newest:
      return 'Newest';
    case GallerySortOption.oldest:
      return 'Oldest';
    case GallerySortOption.ratingHigh:
      return 'Rating high';
    case GallerySortOption.ratingLow:
      return 'Rating low';
    case GallerySortOption.resolutionHigh:
      return 'Resolution';
    case GallerySortOption.durationHigh:
      return 'Playback long';
    case GallerySortOption.durationLow:
      return 'Playback short';
    case GallerySortOption.generationDurationHigh:
      return 'Generation long';
    case GallerySortOption.generationDurationLow:
      return 'Generation short';
  }
}

String galleryMediaTypeFilterLabel(GalleryMediaTypeFilter option) {
  switch (option) {
    case GalleryMediaTypeFilter.all:
      return 'All';
    case GalleryMediaTypeFilter.images:
      return 'Images';
    case GalleryMediaTypeFilter.gifs:
      return 'GIFs';
    case GalleryMediaTypeFilter.videos:
      return 'Videos';
  }
}

String galleryGroupLabel(GalleryGroupOption option) {
  switch (option) {
    case GalleryGroupOption.none:
      return 'None';
    case GalleryGroupOption.model:
      return 'Model';
    case GalleryGroupOption.rating:
      return 'Rating';
    case GalleryGroupOption.mediaType:
      return 'Media type';
  }
}

String galleryFilterLabel(GalleryViewModel browser) {
  final parts = <String>[];
  if (browser.mediaTypeFilter != GalleryMediaTypeFilter.all) {
    parts.add(galleryMediaTypeFilterLabel(browser.mediaTypeFilter));
  }
  if ((browser.modelFilter ?? 'All models') != 'All models') {
    parts.add('Model');
  }
  if (browser.includeTags.isNotEmpty) {
    parts.add(
      browser.includeTags.length == 1
          ? '1 tag'
          : '${browser.includeTags.length} tags',
    );
  }
  if (browser.excludeTags.isNotEmpty) {
    parts.add(
      browser.excludeTags.length == 1
          ? 'Exclude 1 tag'
          : 'Exclude ${browser.excludeTags.length} tags',
    );
  }
  if (browser.minRating > 0) {
    parts.add('${browser.minRating}+ stars');
  }
  if (browser.searchQuery.trim().isNotEmpty) {
    parts.add('Search');
  }
  if (browser.showDeleted) {
    parts.add('Deleted');
  }
  if (!browser.showPlaceholders) {
    parts.add('No placeholders');
  }
  return parts.isEmpty ? 'All media' : parts.join(' • ');
}

bool hasActiveGalleryFilters(GalleryViewModel browser) {
  return browser.searchQuery.trim().isNotEmpty ||
      browser.mediaTypeFilter != GalleryMediaTypeFilter.all ||
      (browser.modelFilter ?? 'All models') != 'All models' ||
      browser.includeTags.isNotEmpty ||
      browser.excludeTags.isNotEmpty ||
      browser.minRating > 0 ||
      browser.showDeleted ||
      !browser.showPlaceholders ||
      browser.sortOption != GallerySortOption.newest ||
      browser.groupOption != GalleryGroupOption.none;
}

List<Widget> activeGalleryFilterChips({
  required GalleryViewModel browser,
  required VoidCallback onClearSearch,
}) {
  final chips = <Widget>[];
  if (browser.searchQuery.trim().isNotEmpty) {
    chips.add(
      ActiveChip(
        label: 'Search: ${browser.searchQuery.trim()}',
        onDeleted: onClearSearch,
      ),
    );
  }
  if (browser.mediaTypeFilter != GalleryMediaTypeFilter.all) {
    chips.add(
      ActiveChip(
        label: 'Type: ${galleryMediaTypeFilterLabel(browser.mediaTypeFilter)}',
        onDeleted: () => browser.setMediaTypeFilter(GalleryMediaTypeFilter.all),
      ),
    );
  }
  if ((browser.modelFilter ?? 'All models') != 'All models') {
    chips.add(
      ActiveChip(
        label: 'Model: ${browser.modelFilter}',
        onDeleted: () => browser.setModelFilter('All models'),
      ),
    );
  }
  for (final tag in browser.includeTags) {
    chips.add(
      ActiveChip(
        label: 'Tag: $tag',
        onDeleted: () => browser.setIncludeTags(
          browser.includeTags.where((item) => item != tag).toList(),
        ),
      ),
    );
  }
  for (final tag in browser.excludeTags) {
    chips.add(
      ActiveChip(
        label: 'Without: $tag',
        onDeleted: () => browser.setExcludeTags(
          browser.excludeTags.where((item) => item != tag).toList(),
        ),
      ),
    );
  }
  if (browser.minRating > 0) {
    chips.add(
      ActiveChip(
        label: 'Rating: ${browser.minRating}+',
        onDeleted: () => browser.setMinRating(0),
      ),
    );
  }
  if (browser.showDeleted) {
    chips.add(
      ActiveChip(
        label: 'Deleted media',
        onDeleted: () => browser.setShowDeleted(false),
      ),
    );
  }
  if (!browser.showPlaceholders) {
    chips.add(
      ActiveChip(
        label: 'No placeholders',
        onDeleted: () => browser.setShowPlaceholders(true),
      ),
    );
  }
  if (browser.sortOption != GallerySortOption.newest) {
    chips.add(
      ActiveChip(
        label: 'Sort: ${gallerySortLabel(browser.sortOption)}',
        onDeleted: () => browser.setSortOption(GallerySortOption.newest),
      ),
    );
  }
  if (browser.groupOption != GalleryGroupOption.none) {
    chips.add(
      ActiveChip(
        label: 'Group: ${galleryGroupLabel(browser.groupOption)}',
        onDeleted: () => browser.setGroupOption(GalleryGroupOption.none),
      ),
    );
  }
  return chips;
}
