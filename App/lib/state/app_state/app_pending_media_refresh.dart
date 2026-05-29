import 'package:dio/dio.dart';

import '../../api_client.dart';
import '../../models/media.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppPendingMediaRefreshDependencies {
  const AppPendingMediaRefreshDependencies({
    required this.mediaRuntime,
    required this.jobRuntime,
    required this.replaceGalleryItem,
    required this.removeGalleryItemById,
    required this.latestCompletedGalleryItem,
  });

  final AppMediaRuntimeState mediaRuntime;
  final AppJobRuntimeState jobRuntime;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(String mediaId) removeGalleryItemById;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
}

class AppPendingMediaRefresh {
  AppPendingMediaRefresh(this.dependencies);

  final AppPendingMediaRefreshDependencies dependencies;

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
