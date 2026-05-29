import 'dart:async';

import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/features/jobs/domain/job_status_selectors.dart';
import 'package:flutter_app/features/gallery/controllers/pending_media_refresh_controller.dart';
import 'package:flutter_app/features/generate/controllers/video_result_preview_controller.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';


class FetchedJobSynchronizerDependencies {
  const FetchedJobSynchronizerDependencies({
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.pendingMediaRefreshController,
    required this.replaceGalleryItem,
    required this.syncDeletedScalingSource,
    required this.latestCompletedGalleryItem,
    required this.videoResultPreviewController,
  });

  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final PendingMediaRefreshController pendingMediaRefreshController;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(JobStatus job) syncDeletedScalingSource;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
  final VideoResultPreviewController videoResultPreviewController;
}

class FetchedJobSynchronizer {
  const FetchedJobSynchronizer(this.dependencies);

  final FetchedJobSynchronizerDependencies dependencies;

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
      unawaited(dependencies.videoResultPreviewController.refresh(job.jobId));
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
        !dependencies.pendingMediaRefreshController.activeJobReferencesMedia(
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
          : firstPrimaryWorkflowJob(fetchedJobs);
    }
  }
}
