import 'dart:async';

import '../../models/jobs.dart';
import '../../models/media.dart';
import '../chat_job_message_state.dart';
import '../job_notification_state.dart';
import 'app_video_result_preview_refresher.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppTerminalJobHandlerDependencies {
  const AppTerminalJobHandlerDependencies({
    required this.connection,
    required this.activity,
    required this.mediaRuntime,
    required this.jobNotifications,
    required this.chatJobMessages,
    required this.loadErrors,
    required this.replaceGalleryItem,
    required this.syncDeletedScalingSource,
    required this.latestCompletedGalleryItem,
    required this.videoResultPreviewRefresher,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final AppMediaRuntimeState mediaRuntime;
  final JobNotificationState jobNotifications;
  final ChatJobMessageState Function() chatJobMessages;
  final Future<void> Function({bool silent}) loadErrors;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(JobStatus job) syncDeletedScalingSource;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
  final AppVideoResultPreviewRefresher videoResultPreviewRefresher;
  final void Function() notifyChanged;
}

class AppTerminalJobHandler {
  const AppTerminalJobHandler(this.dependencies);

  final AppTerminalJobHandlerDependencies dependencies;

  Future<ImageRecord?> handle(
    JobStatus job, {
    String? expectedResultImageId,
  }) async {
    await dependencies.jobNotifications.cancelRunningJob(jobId: job.jobId);
    if (job.type != 'chat_message') {
      await dependencies.jobNotifications.showTerminalJob(job);
    }
    _removeMissingExpectedResult(job, expectedResultImageId);
    _syncTerminalResult(job);
    dependencies.syncDeletedScalingSource(job);
    await _handleTerminalMessage(job);
    dependencies.activity.runningJob = false;
    dependencies.notifyChanged();
    return job.result;
  }

  void _removeMissingExpectedResult(
    JobStatus job,
    String? expectedResultImageId,
  ) {
    if (job.result != null || expectedResultImageId == null) {
      return;
    }
    dependencies.mediaRuntime.gallery.removeWhere(
      (item) => item.id == expectedResultImageId,
    );
    if (dependencies.mediaRuntime.latestImage?.id == expectedResultImageId) {
      dependencies.mediaRuntime.latestImage = dependencies
          .latestCompletedGalleryItem(dependencies.mediaRuntime.gallery);
    }
  }

  void _syncTerminalResult(JobStatus job) {
    final result = job.result;
    if (result == null) {
      return;
    }
    dependencies.replaceGalleryItem(result);
    if (result.isReady) {
      dependencies.mediaRuntime.latestImage = result;
    }
    if (result.isVideo && result.posterUrl == null) {
      unawaited(dependencies.videoResultPreviewRefresher.refresh(job.jobId));
    }
  }

  Future<void> _handleTerminalMessage(JobStatus job) async {
    if (job.type == 'chat_message') {
      await dependencies.chatJobMessages().handleTerminalJob(job);
      return;
    }
    if (job.status != 'failed') {
      return;
    }
    final jobError = job.error?.trim();
    dependencies.connection.message = jobError == null || jobError.isEmpty
        ? 'The job could not be completed.'
        : jobError;
    unawaited(dependencies.loadErrors(silent: true));
  }
}
