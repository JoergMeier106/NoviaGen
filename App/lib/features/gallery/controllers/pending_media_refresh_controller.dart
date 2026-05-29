import 'package:dio/dio.dart';

import 'package:noviagen/api_client.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';
import 'package:noviagen/app/runtime/media_runtime_store.dart';


class PendingMediaRefreshControllerDependencies {
  const PendingMediaRefreshControllerDependencies({
    required this.mediaRuntime,
    required this.jobRuntime,
    required this.replaceGalleryItem,
    required this.removeGalleryItemById,
    required this.latestCompletedGalleryItem,
  });

  final MediaRuntimeStore mediaRuntime;
  final JobRuntimeStore jobRuntime;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(String mediaId) removeGalleryItemById;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
}

class PendingMediaRefreshController {
  PendingMediaRefreshController(this.dependencies);

  final PendingMediaRefreshControllerDependencies dependencies;

  Future<void> refresh(ApiClient client) async {
    for (final mediaId in _pendingGalleryMediaIds()) {
      try {
        final image = await client.fetchImage(mediaId);
        _syncPendingGalleryImage(image);
      } on DioException catch (error) {
        _removeMissingPendingGalleryImage(mediaId, error);
      } catch (_) {
        continue;
      }
    }
  }

  bool activeJobReferencesMedia(String mediaId) {
    for (final job in dependencies.jobRuntime.jobs) {
      if (job.canCancel && job.result?.id == mediaId) {
        return true;
      }
    }
    return dependencies.jobRuntime.latestJob?.canCancel == true &&
        dependencies.jobRuntime.latestJob?.result?.id == mediaId;
  }

  bool get hasPendingMedia {
    if (dependencies.mediaRuntime.latestImage?.isPending ?? false) {
      return true;
    }
    for (final item in dependencies.mediaRuntime.gallery) {
      if (item.isPending) {
        return true;
      }
    }
    return false;
  }

  Set<String> _pendingGalleryMediaIds() {
    final pendingIds = <String>{};
    final latest = dependencies.mediaRuntime.latestImage;
    if (latest != null && latest.isPending) {
      pendingIds.add(latest.id);
    }
    for (final item in dependencies.mediaRuntime.gallery) {
      if (item.isPending) {
        pendingIds.add(item.id);
      }
    }
    return pendingIds;
  }

  void _syncPendingGalleryImage(ImageRecord image) {
    dependencies.replaceGalleryItem(image);
    if (dependencies.mediaRuntime.latestImage?.id == image.id) {
      dependencies.mediaRuntime.latestImage = image;
    } else if (dependencies.mediaRuntime.latestImage == null && image.isReady) {
      dependencies.mediaRuntime.latestImage = image;
    }
  }

  void _removeMissingPendingGalleryImage(String mediaId, DioException error) {
    if (error.response?.statusCode != 404 ||
        activeJobReferencesMedia(mediaId)) {
      return;
    }
    dependencies.removeGalleryItemById(mediaId);
    if (dependencies.mediaRuntime.latestImage?.id == mediaId) {
      dependencies.mediaRuntime.latestImage = dependencies
          .latestCompletedGalleryItem(dependencies.mediaRuntime.gallery);
    }
  }
}
