import 'dart:async';

import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/chat/controllers/chat_job_message_controller.dart';
import 'package:noviagen/features/jobs/services/job_notification_service.dart';
import 'package:noviagen/features/generate/controllers/video_result_preview_controller.dart';
import 'package:noviagen/app/runtime/app_activity_store.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/media_runtime_store.dart';


class TerminalJobHandlerDependencies {
  const TerminalJobHandlerDependencies({
    required this.connection,
    required this.activity,
    required this.mediaRuntime,
    required this.jobNotifications,
    required this.chatJobMessages,
    required this.loadErrors,
    required this.replaceGalleryItem,
    required this.syncDeletedScalingSource,
    required this.latestCompletedGalleryItem,
    required this.videoResultPreviewController,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final MediaRuntimeStore mediaRuntime;
  final JobNotificationService jobNotifications;
  final ChatJobMessageController Function() chatJobMessages;
  final Future<void> Function({bool silent}) loadErrors;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(JobStatus job) syncDeletedScalingSource;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
  final VideoResultPreviewController videoResultPreviewController;
  final void Function() notifyChanged;
}

class TerminalJobHandler {
  const TerminalJobHandler(this.dependencies);

  final TerminalJobHandlerDependencies dependencies;

  Future<ImageRecord?> handle(
    JobStatus job, {
    String? expectedResultImageId,
  }) async {
    await dependencies.jobNotifications.cancelRunningJob(jobId: job.jobId);
    if (job.type != 'chat_message' && job.isPrimaryWorkflowJob) {
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
      unawaited(dependencies.videoResultPreviewController.refresh(job.jobId));
    }
  }

  Future<void> _handleTerminalMessage(JobStatus job) async {
    if (job.type == 'chat_message') {
      await dependencies.chatJobMessages().handleTerminalJob(job);
      return;
    }
    if (!job.isPrimaryWorkflowJob) {
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
