import 'dart:async';

import '../../models/jobs.dart';
import '../../models/media.dart';
import '../app_navigation_state.dart';
import '../request_errors.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppJobQueueDependencies {
  const AppJobQueueDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.navigation,
    required this.replaceJob,
    required this.replaceGalleryItem,
    required this.syncMediaRefreshTimer,
    required this.pollJob,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final AppJobRuntimeState jobRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final AppNavigationState Function() navigation;
  final void Function(JobStatus job) replaceJob;
  final void Function(ImageRecord image) replaceGalleryItem;
  final VoidCallback syncMediaRefreshTimer;
  final Future<ImageRecord?> Function(
    String jobId, {
    String? expectedResultImageId,
  })
  pollJob;
  final void Function() notifyChanged;
}

class AppJobQueueController {
  AppJobQueueController(this.dependencies);

  final AppJobQueueDependencies dependencies;

  ImageRecord? registerQueuedJob(JobStatus job, {String? queuedMessage}) {
    dependencies.jobRuntime.latestJob = job;
    dependencies.replaceJob(job);
    final result = job.result;
    if (result != null) {
      dependencies.replaceGalleryItem(result);
      if (result.isReady) {
        dependencies.mediaRuntime.latestImage = result;
      }
    }
    dependencies.activity.runningJob = job.canCancel;
    dependencies.notifyChanged();
    dependencies.syncMediaRefreshTimer();
    if (queuedMessage != null && queuedMessage.isNotEmpty) {
      dependencies.navigation().announceQueuedJob(queuedMessage);
    }
    unawaited(
      _pollQueuedJobSafely(
        job.jobId,
        expectedResultImageId: result?.id,
      ),
    );
    return result;
  }

  Future<void> _pollQueuedJobSafely(
    String jobId, {
    String? expectedResultImageId,
  }) async {
    try {
      await dependencies.pollJob(
        jobId,
        expectedResultImageId: expectedResultImageId,
      );
    } catch (_) {
      // The accepted job remains visible through normal job refresh.
    }
  }

  Future<JobStatus?> waitForTerminalState(String jobId) async {
    final client = dependencies.connection.api;
    if (client == null) {
      return null;
    }

    var consecutiveFailures = 0;
    while (true) {
      try {
        final job = await client.getJob(jobId);
        consecutiveFailures = 0;
        if (job.isTerminal) {
          return job;
        }
      } catch (error) {
        consecutiveFailures += 1;
        if (consecutiveFailures >= 8 ||
            (!isConnectionError(error) && !isTimeoutError(error))) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 250 * consecutiveFailures),
        );
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}

typedef VoidCallback = void Function();
