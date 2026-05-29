import 'dart:async';

import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/features/gallery/state/gallery_browser_store.dart';
import 'package:flutter_app/features/generate/state/generation_source_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';


class MediaIndexSynchronizerDependencies {
  const MediaIndexSynchronizerDependencies({
    required this.mediaRuntime,
    required this.jobRuntime,
    required this.galleryBrowser,
    required this.generationSources,
    required this.loadGalleryFirstPage,
  });

  final MediaRuntimeStore mediaRuntime;
  final JobRuntimeStore jobRuntime;
  final GalleryBrowserStore Function() galleryBrowser;
  final GenerationSourceStore Function() generationSources;
  final Future<void> Function() loadGalleryFirstPage;
}

class MediaIndexSynchronizer {
  MediaIndexSynchronizer(this.dependencies);

  final MediaIndexSynchronizerDependencies dependencies;

  ImageRecord? latestCompletedGalleryItem([List<ImageRecord>? items]) {
    final source = items ?? dependencies.mediaRuntime.gallery;
    for (final item in source) {
      if (item.isReady) {
        return item;
      }
    }
    return null;
  }

  ImageRecord? findKnownMediaById(String imageId) {
    if (dependencies.mediaRuntime.latestImage?.id == imageId) {
      return dependencies.mediaRuntime.latestImage;
    }
    for (final item in dependencies.mediaRuntime.gallery) {
      if (item.id == imageId) {
        return item;
      }
    }
    for (final job in dependencies.jobRuntime.jobs) {
      final result = job.result;
      if (result?.id == imageId) {
        return result;
      }
    }
    return null;
  }

  void syncDeletedScalingSource(JobStatus job) {
    if (!_shouldDeleteScalingSource(job)) {
      return;
    }
    final sourceImageId = _jobSourceImageId(job);
    if (sourceImageId == null) {
      return;
    }
    if (dependencies.galleryBrowser().showDeleted) {
      unawaited(dependencies.loadGalleryFirstPage());
    } else {
      removeGalleryItemById(sourceImageId);
    }
    if (dependencies.mediaRuntime.latestImage?.id == sourceImageId) {
      dependencies.mediaRuntime.latestImage = latestCompletedGalleryItem(
        dependencies.mediaRuntime.gallery,
      );
    }
  }

  void replaceJob(JobStatus job) {
    final index = dependencies.jobRuntime.jobs.indexWhere(
      (item) => item.jobId == job.jobId,
    );
    if (index >= 0) {
      dependencies.jobRuntime.jobs[index] = job;
    } else {
      dependencies.jobRuntime.jobs.insert(0, job);
    }
  }

  void removeGalleryItemById(String imageId) {
    final removed = dependencies.mediaRuntime.gallery
        .where((item) => item.id == imageId)
        .toList();
    if (removed.isNotEmpty) {
      dependencies.mediaRuntime.gallery = dependencies.mediaRuntime.gallery
          .where((item) => item.id != imageId)
          .toList();
      dependencies.galleryBrowser().decrementTotalCount(removed.length);
    }
    dependencies.generationSources().clearStoredSourceById(imageId);
  }

  void replaceGalleryItem(ImageRecord image) {
    final index = dependencies.mediaRuntime.gallery.indexWhere(
      (item) => item.id == image.id,
    );
    final matchesQuery = dependencies.galleryBrowser().matches(image);
    if (index >= 0 && !matchesQuery) {
      dependencies.mediaRuntime.gallery.removeAt(index);
      dependencies.galleryBrowser().decrementTotalCount(1);
      return;
    }
    if (!matchesQuery) {
      return;
    }
    if (index >= 0) {
      dependencies.mediaRuntime.gallery[index] = image;
    } else {
      dependencies.mediaRuntime.gallery.insert(0, image);
      dependencies.galleryBrowser().incrementTotalCount();
    }
    dependencies.generationSources().replaceStoredSource(image);
    sortLoadedGalleryItems();
  }

  void sortLoadedGalleryItems() {
    dependencies.mediaRuntime.gallery.sort(
      dependencies.galleryBrowser().compareItems,
    );
  }

  bool _shouldDeleteScalingSource(JobStatus job) {
    return (job.type == 'upscale' || job.type == 'upscale_video') &&
        job.status == 'completed' &&
        (job.payload['delete_source_after_finish'] as bool? ?? false);
  }

  String? _jobSourceImageId(JobStatus job) {
    final rawValue = job.payload['source_image_id'] ?? job.payload['image_id'];
    final sourceImageId = rawValue?.toString().trim() ?? '';
    return sourceImageId.isEmpty ? null : sourceImageId;
  }
}
