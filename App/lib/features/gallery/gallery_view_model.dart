import 'package:flutter/foundation.dart';

import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/generate/controllers/generation_source_controller.dart';
import 'package:noviagen/features/gallery/controllers/media_job_controller.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';
import 'package:noviagen/app/runtime/media_runtime_store.dart';
import 'package:noviagen/features/gallery/state/gallery_browser_store.dart';
import 'package:noviagen/features/jobs/controllers/job_operations_controller.dart';
import 'package:noviagen/features/gallery/controllers/media_actions_controller.dart';

abstract class GalleryViewModel implements Listenable {
  String get baseUrl;
  String? get message;
  List<ImageRecord> get gallery;
  List<String> get suggestedTags;
  bool get hasMore;
  String get searchQuery;
  String? get modelFilter;
  List<String> get includeTags;
  List<String> get excludeTags;
  int get minRating;
  GalleryMediaTypeFilter get mediaTypeFilter;
  bool get showDeleted;
  bool get showPlaceholders;
  List<String> get modelFilters;
  List<String> get availableTags;
  int get slideshowIntervalSeconds;
  int get currentPage;
  int get totalCount;
  bool get loadingFirstPage;
  bool get loadingNextPage;
  GallerySortOption get sortOption;
  GalleryGroupOption get groupOption;

  void setSearchQuery(String value);
  void setModelFilter(String? value);
  void setIncludeTags(List<String> values);
  void setExcludeTags(List<String> values);
  void setMinRating(int value);
  void setSortOption(GallerySortOption value);
  void setMediaTypeFilter(GalleryMediaTypeFilter value);
  void setGroupOption(GalleryGroupOption value);
  void setShowDeleted(bool value);
  void setShowPlaceholders(bool value);
  void resetPreferences();
  List<GalleryGroupSection> groupItems(List<ImageRecord> items);
  Future<void> loadGalleryFirstPage();
  Future<void> loadGalleryNextPage();
  ImageRecord? findKnownMediaById(String imageId);
  Future<ImageRecord?> fetchImageById(String imageId, {bool refresh = false});
  Future<String?> deleteStoredImage(String imageId);
  Future<String?> restoreDeletedImage(String imageId);
  Future<String?> downloadStoredImage(ImageRecord image);
  Future<void> setImageRating(String imageId, int rating);
  Future<void> setImageTags(String imageId, List<String> tags);
  Future<void> generateImageTags(String imageId);
  Future<void> deleteTag(String tag);
  JobStatus? jobForImage(String imageId);
  Future<void> cancelJob(String jobId);
  void attachStoredImageForGeneration(ImageRecord image);
  void attachStoredImageForVideoGeneration(ImageRecord image);
  Future<ImageRecord?> regenerateImage(ImageRecord image);
  Future<ImageRecord?> regenerateVideo(ImageRecord image);
  Future<ImageRecord?> upscaleImage(ImageRecord image, double scaleFactor);
  Future<ImageRecord?> convertVideoToGif(ImageRecord image);
  Future<ImageRecord?> generateAudioVideo(ImageRecord image);
  Future<ImageRecord?> createPromptAndAnimateImage(ImageRecord image);
}

class AppGalleryViewModel implements GalleryViewModel {
  AppGalleryViewModel({
    required this.changes,
    required this.connection,
    required this.mediaRuntime,
    required this.browser,
    required this.jobRuntime,
    required this.actions,
    required this.jobOperations,
    required this.generationSourceController,
    required this.mediaJobController,
  });

  final Listenable changes;
  final AppConnectionStore connection;
  final MediaRuntimeStore mediaRuntime;
  final GalleryBrowserStore browser;
  final JobRuntimeStore jobRuntime;
  final MediaActionsController actions;
  final JobOperationsController jobOperations;
  final GenerationSourceController generationSourceController;
  final MediaJobController mediaJobController;

  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      changes.removeListener(listener);

  @override
  String get baseUrl => connection.baseUrl;

  @override
  String? get message => connection.message;

  @override
  List<ImageRecord> get gallery => mediaRuntime.gallery;

  @override
  List<String> get suggestedTags => mediaRuntime.suggestedTags;

  @override
  bool get hasMore => browser.hasMore;

  @override
  String get searchQuery => browser.searchQuery;

  @override
  String? get modelFilter => browser.modelFilter;

  @override
  List<String> get includeTags => browser.includeTags;

  @override
  List<String> get excludeTags => browser.excludeTags;

  @override
  int get minRating => browser.minRating;

  @override
  GalleryMediaTypeFilter get mediaTypeFilter => browser.mediaTypeFilter;

  @override
  bool get showDeleted => browser.showDeleted;

  @override
  bool get showPlaceholders => browser.showPlaceholders;

  @override
  List<String> get modelFilters => browser.modelFilters;

  @override
  List<String> get availableTags => browser.availableTags;

  @override
  int get slideshowIntervalSeconds => browser.slideshowIntervalSeconds;

  @override
  int get currentPage => browser.currentPage;

  @override
  int get totalCount => browser.totalCount;

  @override
  bool get loadingFirstPage => browser.loadingFirstPage;

  @override
  bool get loadingNextPage => browser.loadingNextPage;

  @override
  GallerySortOption get sortOption => browser.sortOption;

  @override
  GalleryGroupOption get groupOption => browser.groupOption;

  @override
  void setSearchQuery(String value) => browser.setSearchQuery(value);

  @override
  void setModelFilter(String? value) => browser.setModelFilter(value);

  @override
  void setIncludeTags(List<String> values) => browser.setIncludeTags(values);

  @override
  void setExcludeTags(List<String> values) => browser.setExcludeTags(values);

  @override
  void setMinRating(int value) => browser.setMinRating(value);

  @override
  void setSortOption(GallerySortOption value) => browser.setSortOption(value);

  @override
  void setMediaTypeFilter(GalleryMediaTypeFilter value) =>
      browser.setMediaTypeFilter(value);

  @override
  void setGroupOption(GalleryGroupOption value) =>
      browser.setGroupOption(value);

  @override
  void setShowDeleted(bool value) => browser.setShowDeleted(value);

  @override
  void setShowPlaceholders(bool value) => browser.setShowPlaceholders(value);

  @override
  void resetPreferences() => browser.resetPreferences();

  @override
  List<GalleryGroupSection> groupItems(List<ImageRecord> items) =>
      browser.groupItems(items);

  @override
  Future<void> loadGalleryFirstPage() => actions.loadGalleryFirstPage();

  @override
  Future<void> loadGalleryNextPage() => actions.loadGalleryNextPage();

  @override
  ImageRecord? findKnownMediaById(String imageId) =>
      actions.findKnownMediaById(imageId);

  @override
  Future<ImageRecord?> fetchImageById(String imageId, {bool refresh = false}) =>
      actions.fetchImageById(imageId, refresh: refresh);

  @override
  Future<String?> deleteStoredImage(String imageId) =>
      actions.deleteStoredImage(imageId);

  @override
  Future<String?> restoreDeletedImage(String imageId) =>
      actions.restoreDeletedImage(imageId);

  @override
  Future<String?> downloadStoredImage(ImageRecord image) =>
      actions.downloadStoredImage(image);

  @override
  Future<void> setImageRating(String imageId, int rating) =>
      actions.setImageRating(imageId, rating);

  @override
  Future<void> setImageTags(String imageId, List<String> tags) =>
      actions.setImageTags(imageId, tags);

  @override
  Future<void> generateImageTags(String imageId) =>
      actions.generateImageTags(imageId);

  @override
  Future<void> deleteTag(String tag) => actions.deleteTag(tag);

  @override
  JobStatus? jobForImage(String imageId) => jobRuntime.jobForImage(imageId);

  @override
  Future<void> cancelJob(String jobId) => jobOperations.cancelJob(jobId);

  @override
  void attachStoredImageForGeneration(ImageRecord image) =>
      generationSourceController.attachStoredImageForGeneration(image);

  @override
  void attachStoredImageForVideoGeneration(ImageRecord image) =>
      generationSourceController.attachStoredImageForVideoGeneration(image);

  @override
  Future<ImageRecord?> regenerateImage(ImageRecord image) =>
      mediaJobController.regenerateImage(image);

  @override
  Future<ImageRecord?> regenerateVideo(ImageRecord image) =>
      mediaJobController.regenerateVideo(image);

  @override
  Future<ImageRecord?> upscaleImage(ImageRecord image, double scaleFactor) =>
      mediaJobController.upscaleImage(image, scaleFactor);

  @override
  Future<ImageRecord?> convertVideoToGif(ImageRecord image) =>
      mediaJobController.convertVideoToGif(image);

  @override
  Future<ImageRecord?> generateAudioVideo(ImageRecord image) =>
      mediaJobController.generateAudioVideo(image);

  @override
  Future<ImageRecord?> createPromptAndAnimateImage(ImageRecord image) =>
      mediaJobController.createPromptAndAnimateImage(image);
}
