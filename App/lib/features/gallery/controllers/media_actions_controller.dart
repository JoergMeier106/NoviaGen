import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:noviagen/api_client.dart';
import 'package:noviagen/device_downloads.dart';
import 'package:noviagen/models/gallery.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/gallery/state/gallery_browser_store.dart';
import 'package:noviagen/features/gallery/domain/media_file_naming.dart';
import 'package:noviagen/shared/request_errors.dart';

class MediaActionsController {
  MediaActionsController({
    required this.api,
    required this.galleryBrowser,
    required this.gallery,
    required this.setGallery,
    required this.latestImage,
    required this.setLatestImage,
    required this.setSuggestedTags,
    required this.setImportingGalleryMedia,
    required this.findKnownMedia,
    required this.removeGalleryItem,
    required this.replaceGalleryItem,
    required this.loadJobs,
    required this.syncMediaRefreshTimer,
    required this.setMessage,
    required this.setRequestError,
    required this.selectedMetadataModelName,
    required this.onChanged,
    this.galleryPageSize = 30,
  });

  static const defaultGalleryPageSize = 30;

  final ApiClient? Function() api;
  final int galleryPageSize;
  final GalleryBrowserStore galleryBrowser;
  final List<ImageRecord> Function() gallery;
  final void Function(List<ImageRecord> value) setGallery;
  final ImageRecord? Function() latestImage;
  final void Function(ImageRecord? value) setLatestImage;
  final void Function(List<String> value) setSuggestedTags;
  final void Function(bool value) setImportingGalleryMedia;
  final ImageRecord? Function(String imageId) findKnownMedia;
  final void Function(String imageId) removeGalleryItem;
  final void Function(ImageRecord image) replaceGalleryItem;
  final Future<void> Function() loadJobs;
  final VoidCallback syncMediaRefreshTimer;
  final void Function(String? value) setMessage;
  final RequestErrorHandler setRequestError;
  final String? Function(ImageRecord image) selectedMetadataModelName;
  final void Function() onChanged;
  final ImagePicker _imagePicker = ImagePicker();

  ImageRecord? findKnownMediaById(String imageId) {
    return findKnownMedia(imageId);
  }

  Future<ImageRecord?> fetchImageById(
    String imageId, {
    bool refresh = false,
  }) async {
    final trimmedId = imageId.trim();
    if (trimmedId.isEmpty) {
      return null;
    }
    if (!refresh) {
      final known = findKnownMedia(trimmedId);
      if (known != null) {
        return known;
      }
    }

    final client = api();
    if (client == null) {
      return findKnownMedia(trimmedId);
    }
    try {
      final image = await client.fetchImage(trimmedId);
      replaceGalleryItem(image);
      if (latestImage()?.id == trimmedId) {
        setLatestImage(image);
      }
      onChanged();
      return image;
    } catch (_) {
      return findKnownMedia(trimmedId);
    }
  }

  Future<void> storeLatest() async {
    await loadLatestResult(silent: true);
    final latest = latestImage();
    setMessage(_storeLatestMessage(latest));
    onChanged();
  }

  Future<void> loadLatestResult({bool silent = false}) async {
    final client = api();
    if (client == null) {
      return;
    }

    try {
      final page = await client.fetchGalleryImagesPage(page: 1, pageSize: 1);
      setLatestImage(_latestCompletedGalleryItem(page.items));
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        setLatestImage(null);
      } else if (!silent) {
        setRequestError(
          error,
          generalMessage:
              'Couldn\'t load the latest result right now. Please try again.',
        );
      }
    } catch (error) {
      if (!silent) {
        setRequestError(
          error,
          generalMessage:
              'Couldn\'t load the latest result right now. Please try again.',
        );
      }
    } finally {
      onChanged();
    }
  }

  Future<void> loadGalleryFirstPage() async {
    final client = api();
    if (client == null) {
      return;
    }

    galleryBrowser.loadingFirstPage = true;
    onChanged();
    try {
      final responses = await Future.wait<Object>([
        _fetchGalleryPage(client, page: 1),
        client.fetchGalleryFilters(includeDeleted: galleryBrowser.showDeleted),
      ]);
      final page = responses[0] as GalleryPageResponse;
      final filters = responses[1] as GalleryFiltersResponse;
      setGallery(page.items);
      galleryBrowser.updatePage(page);
      galleryBrowser.updateFilters(filters);
      setSuggestedTags(filters.tags);
      galleryBrowser.sortLoadedItems();
      setLatestImage(_latestCompletedGalleryItem(gallery()));
      syncMediaRefreshTimer();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t load the gallery right now. Please try again.',
      );
    } finally {
      galleryBrowser.loadingFirstPage = false;
      onChanged();
    }
  }

  Future<void> loadGalleryNextPage() async {
    final client = api();
    if (client == null ||
        galleryBrowser.loadingFirstPage ||
        galleryBrowser.loadingNextPage ||
        !galleryBrowser.hasMore) {
      return;
    }

    galleryBrowser.loadingNextPage = true;
    onChanged();
    try {
      final page = await _fetchGalleryPage(
        client,
        page: galleryBrowser.currentPage + 1,
      );
      setGallery(_mergeGalleryPageItems(page.items));
      galleryBrowser.updatePage(page);
      galleryBrowser.sortLoadedItems();
      setLatestImage(_latestCompletedGalleryItem(gallery()));
      syncMediaRefreshTimer();
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t load more gallery items right now. Please try again.',
      );
    } finally {
      galleryBrowser.loadingNextPage = false;
      onChanged();
    }
  }

  Future<String?> deleteStoredImage(String imageId) async {
    final client = api();
    if (client == null) {
      return null;
    }

    try {
      ImageRecord? item;
      for (final entry in gallery()) {
        if (entry.id == imageId) {
          item = entry;
          break;
        }
      }
      await client.deleteImage(imageId);
      if (galleryBrowser.showDeleted && item?.isReady == true) {
        await loadGalleryFirstPage();
      } else {
        removeGalleryItem(imageId);
      }
      await loadJobs();
      await loadLatestResult(silent: true);
      if (galleryBrowser.hasMore && gallery().isNotEmpty) {
        unawaited(loadGalleryNextPage());
      }
      onChanged();
      if (item?.isPending == true) {
        return item?.isVideo == true
            ? 'Queued video cancelled.'
            : item?.isGif == true
            ? 'Queued GIF cancelled.'
            : 'Queued image cancelled.';
      }
      return item?.isVideo == true
          ? 'Video moved to deleted media for 5 days.'
          : item?.isGif == true
          ? 'GIF moved to deleted media for 5 days.'
          : 'Image moved to deleted media for 5 days.';
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t delete the item right now. Please try again.',
      );
      onChanged();
      return null;
    }
  }

  Future<String?> restoreDeletedImage(String imageId) async {
    final client = api();
    if (client == null) {
      return null;
    }

    try {
      final restored = await client.restoreImage(imageId);
      if (galleryBrowser.showDeleted) {
        removeGalleryItem(imageId);
      } else {
        replaceGalleryItem(restored);
      }
      final latest = latestImage();
      if (latest?.id == imageId || latest == null) {
        setLatestImage(restored);
      }
      onChanged();
      return restored.isVideo
          ? 'Video restored to the gallery.'
          : restored.isGif
          ? 'GIF restored to the gallery.'
          : 'Image restored to the gallery.';
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t restore the item right now. Please try again.',
      );
      onChanged();
      return null;
    }
  }

  Future<String?> downloadStoredImage(ImageRecord image) async {
    final client = api();
    if (client == null) {
      return null;
    }
    if (!image.canDownload) {
      setMessage('This media is still queued or running.');
      onChanged();
      return null;
    }

    try {
      final bytes = await client.fetchImageBytes(image.fileUrl);
      return DeviceDownloads.saveBytes(
        fileName: 'noviagen_${image.id}',
        bytes: Uint8List.fromList(bytes),
        extension: downloadExtensionForMedia(image),
      );
    } catch (error) {
      setRequestError(
        error,
        generalMessage: image.isVideo
            ? 'Couldn\'t download the video right now. Please try again.'
            : image.isGif
            ? 'Couldn\'t download the GIF right now. Please try again.'
            : 'Couldn\'t download the image right now. Please try again.',
      );
      onChanged();
      return null;
    }
  }

  Future<void> importGalleryImages(ImageSource source) async {
    final client = api();
    if (client == null) {
      setMessage('Set the backend URL before importing media.');
      onChanged();
      return;
    }

    try {
      final files = await _pickImportFiles(source);
      if (files.isEmpty) {
        return;
      }

      setImportingGalleryMedia(true);
      onChanged();

      final response = await client.importGalleryImages(files);
      _applyImportedImages(response.items);
      await _refreshImportFilters(client);
      setMessage(_importResultMessage(response));
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t import the selected image. Please try again.',
      );
    } finally {
      setImportingGalleryMedia(false);
      onChanged();
    }
  }

  Future<void> setImageRating(String imageId, int rating) async {
    final client = api();
    if (client == null) {
      return;
    }
    final image = findKnownMedia(imageId);
    if (image != null && !image.canEditMetadata) {
      setMessage('This media is still queued or running.');
      onChanged();
      return;
    }

    try {
      final updated = await client.setImageRating(imageId, rating);
      replaceGalleryItem(updated);
      if (latestImage()?.id == imageId) {
        setLatestImage(updated);
      }
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t update the rating right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> setImageTags(String imageId, List<String> tags) async {
    final client = api();
    if (client == null) {
      return;
    }
    final image = findKnownMedia(imageId);
    if (image != null && !image.canEditMetadata) {
      setMessage('This media is still queued or running.');
      onChanged();
      return;
    }

    try {
      final updated = await client.setImageTags(imageId, tags);
      replaceGalleryItem(updated);
      if (latestImage()?.id == imageId) {
        setLatestImage(updated);
      }
      galleryBrowser.filterTags = {
        ...galleryBrowser.filterTags,
        ...updated.tags,
      }.toList()..sort();
      setSuggestedTags(galleryBrowser.filterTags);
    } catch (error) {
      setRequestError(
        error,
        generalMessage:
            'Couldn\'t update the tags right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> generateImageTags(String imageId) async {
    final client = api();
    if (client == null) {
      return;
    }
    final image = findKnownMedia(imageId);
    if (image == null) {
      return;
    }
    if (!image.canEditMetadata) {
      setMessage('This media is still queued or running.');
      onChanged();
      return;
    }
    if (!image.isStillImage) {
      setMessage('Tags can only be generated for images.');
      onChanged();
      return;
    }

    final modelName = selectedMetadataModelName(image)?.trim() ?? '';
    if (modelName.isEmpty) {
      setMessage(
        'No vision-capable Ollama model is available for tag generation.',
      );
      onChanged();
      return;
    }

    try {
      final updated = await client.generateImageTags(
        imageId,
        modelName: modelName,
      );
      replaceGalleryItem(updated);
      if (latestImage()?.id == imageId) {
        setLatestImage(updated);
      }
      galleryBrowser.filterTags = {
        ...galleryBrowser.filterTags,
        ...updated.tags,
      }.toList()..sort();
      setSuggestedTags(galleryBrowser.filterTags);
    } catch (error) {
      setRequestError(
        error,
        generalMessage: 'Couldn\'t generate tags right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> deleteTag(String tag) async {
    final client = api();
    if (client == null) {
      return;
    }

    final normalizedTarget = tag.trim().toLowerCase();
    if (normalizedTarget.isEmpty) {
      return;
    }

    try {
      final response = await client.deleteTag(tag);
      setGallery(
        gallery()
            .map(
              (item) => item.copyWith(
                tags: item.tags
                    .where((value) => value.toLowerCase() != normalizedTarget)
                    .toList(),
              ),
            )
            .toList(),
      );
      final latest = latestImage();
      if (latest != null) {
        setLatestImage(
          latest.copyWith(
            tags: latest.tags
                .where((value) => value.toLowerCase() != normalizedTarget)
                .toList(),
          ),
        );
      }
      final updatedTags = response['tags'] as List<dynamic>? ?? <dynamic>[];
      galleryBrowser.filterTags = updatedTags
          .map((item) => item as String)
          .toList();
      setSuggestedTags(galleryBrowser.filterTags);
      galleryBrowser.removeTagFromFilters(normalizedTarget);
      unawaited(galleryBrowser.savePreferences());
      setMessage(
        'Tag removed from ${(response['removed_from_images'] as num?)?.toInt() ?? 0} image(s).',
      );
    } catch (error) {
      setRequestError(
        error,
        generalMessage: 'Couldn\'t delete the tag right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<List<XFile>> _pickImportFiles(ImageSource source) async {
    if (source == ImageSource.gallery) {
      return _imagePicker.pickMultiImage();
    }
    final file = await _imagePicker.pickImage(source: source);
    return file == null ? <XFile>[] : <XFile>[file];
  }

  void _applyImportedImages(List<ImageRecord> images) {
    for (final item in images) {
      replaceGalleryItem(item);
    }
    if (images.isNotEmpty) {
      setLatestImage(images.first);
    }
  }

  Future<void> _refreshImportFilters(ApiClient client) async {
    try {
      final filters = await client.fetchGalleryFilters(
        includeDeleted: galleryBrowser.showDeleted,
      );
      galleryBrowser.updateFilters(filters);
      setSuggestedTags(filters.tags);
    } catch (_) {}
  }

  Future<GalleryPageResponse> _fetchGalleryPage(
    ApiClient client, {
    required int page,
  }) {
    return client.fetchGalleryImagesPage(
      page: page,
      pageSize: galleryPageSize,
      search: galleryBrowser.searchQuery,
      mediaType: galleryBrowser.mediaTypeQueryValue,
      modelId: galleryBrowser.modelFilter,
      includeTags: galleryBrowser.includeTags,
      excludeTags: galleryBrowser.excludeTags,
      minRating: galleryBrowser.minRating,
      sort: galleryBrowser.sortOption.name,
      includeDeleted: galleryBrowser.showDeleted,
      includePlaceholders: galleryBrowser.showPlaceholders,
    );
  }

  List<ImageRecord> _mergeGalleryPageItems(List<ImageRecord> pageItems) {
    return <String, ImageRecord>{
      for (final item in gallery()) item.id: item,
      for (final item in pageItems) item.id: item,
    }.values.toList(growable: false);
  }

  String? _importResultMessage(GalleryImportResponse response) {
    final importedCount = response.items.length;
    final failureCount = response.failures.length;
    if (importedCount > 0 && failureCount == 0) {
      return importedCount == 1
          ? 'Imported 1 image into the gallery.'
          : 'Imported $importedCount images into the gallery.';
    }
    if (importedCount > 0) {
      return 'Imported $importedCount image(s). $failureCount failed.';
    }
    if (failureCount == 1) {
      return response.failures.first.error;
    }
    if (failureCount > 1) {
      return 'Couldn\'t import $failureCount selected images.';
    }
    return null;
  }

  ImageRecord? _latestCompletedGalleryItem(List<ImageRecord> items) {
    for (final item in items) {
      if (item.isReady) {
        return item;
      }
    }
    return null;
  }

  String _storeLatestMessage(ImageRecord? latest) {
    if (latest == null) {
      return 'No generated result is available yet.';
    }
    if (latest.isVideo) {
      return 'Videos are saved automatically after generation.';
    }
    if (latest.isGif) {
      return 'GIFs are saved automatically after generation.';
    }
    return 'Images are saved automatically after generation.';
  }
}
