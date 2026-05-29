import 'dart:async';

import '../../models/jobs.dart';
import '../../models/media.dart';
import 'app_job_status_selectors.dart';
import 'app_pending_media_refresh.dart';
import 'app_video_result_preview_refresher.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppFetchedJobSyncDependencies {
  const AppFetchedJobSyncDependencies({
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.pendingMediaRefresh,
    required this.replaceGalleryItem,
    required this.syncDeletedScalingSource,
    required this.latestCompletedGalleryItem,
    required this.videoResultPreviewRefresher,
  });

  final AppActivityState activity;
  final AppJobRuntimeState jobRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final AppPendingMediaRefresh pendingMediaRefresh;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(JobStatus job) syncDeletedScalingSource;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
  final AppVideoResultPreviewRefresher videoResultPreviewRefresher;
}

class AppFetchedJobSynchronizer {
  const AppFetchedJobSynchronizer(this.dependencies);

  final AppFetchedJobSyncDependencies dependencies;

  void sync(
    List<JobStatus> fetchedJobs, {
    required void Function(JobStatus job) setActiveJob,
  }) {
    final activeJob = firstActiveJob(fetchedJobs);
    for (final job in fetchedJobs) {
      dependencies.syncDeletedScalingSource(job);
      _syncFetchedJobResult(job);
    }
    _syncLatestImage(fetchedJobs);
    if (activeJob != null) {
      setActiveJob(activeJob);
      return;
    }
    _clearFinishedRuntime(fetchedJobs);
  }

  void _syncFetchedJobResult(JobStatus job) {
    final result = job.result;
    if (result == null) {
      return;
    }
    dependencies.replaceGalleryItem(result);
    if (dependencies.mediaRuntime.latestImage?.id == result.id) {
      dependencies.mediaRuntime.latestImage = result;
    }
    if (dependencies.jobRuntime.latestJob?.jobId == job.jobId) {
      dependencies.jobRuntime.latestJob = job;
    }
    if (result.isReady && result.isVideo && result.posterUrl == null) {
      unawaited(dependencies.videoResultPreviewRefresher.refresh(job.jobId));
    }
  }

  void _syncLatestImage(List<JobStatus> fetchedJobs) {
    final newestJobResult = latestReadyJobResult(fetchedJobs);
    if (newestJobResult != null) {
      dependencies.mediaRuntime.latestImage = newestJobResult;
      return;
    }
    final latestImage = dependencies.mediaRuntime.latestImage;
    if (latestImage != null &&
        !dependencies.pendingMediaRefresh.activeJobReferencesMedia(
          latestImage.id,
        )) {
      dependencies.mediaRuntime.latestImage = dependencies
          .latestCompletedGalleryItem(dependencies.mediaRuntime.gallery);
    }
  }

  void _clearFinishedRuntime(List<JobStatus> fetchedJobs) {
    dependencies.activity.runningJob = false;
    if (dependencies.jobRuntime.latestJob?.canCancel ?? false) {
      dependencies.jobRuntime.latestJob = fetchedJobs.isEmpty
          ? null
          : fetchedJobs.first;
    }
  }
}
