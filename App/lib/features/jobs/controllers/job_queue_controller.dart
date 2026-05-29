import 'dart:async';

import 'package:flutter_app/models/jobs.dart';
import 'package:flutter_app/models/media.dart';
import 'package:flutter_app/app/navigation/app_navigation_controller.dart';
import 'package:flutter_app/shared/request_errors.dart';
import 'package:flutter_app/app/runtime/app_activity_store.dart';
import 'package:flutter_app/app/runtime/app_connection_store.dart';
import 'package:flutter_app/app/runtime/job_runtime_store.dart';
import 'package:flutter_app/app/runtime/media_runtime_store.dart';


class JobQueueDependencies {
  const JobQueueDependencies({
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

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final AppNavigationController Function() navigation;
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

class JobQueueController {
  JobQueueController(this.dependencies);

  final JobQueueDependencies dependencies;

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
      // Background polling is best-effort. Once the backend has accepted a job,
      // transient poll failures should not surface as uncaught app errors.
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
