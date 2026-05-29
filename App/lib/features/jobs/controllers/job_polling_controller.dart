import 'dart:async';

import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/chat/controllers/chat_job_message_controller.dart';
import 'package:noviagen/features/jobs/services/job_notification_service.dart';
import 'package:noviagen/features/jobs/services/fetched_job_synchronizer.dart';
import 'package:noviagen/features/jobs/services/job_status_fetcher.dart';
import 'package:noviagen/features/gallery/controllers/pending_media_refresh_controller.dart';
import 'package:noviagen/features/jobs/services/terminal_job_handler.dart';
import 'package:noviagen/features/generate/controllers/video_result_preview_controller.dart';
import 'package:noviagen/app/runtime/app_activity_store.dart';
import 'package:noviagen/app/runtime/app_connection_store.dart';
import 'package:noviagen/app/runtime/job_runtime_store.dart';
import 'package:noviagen/app/runtime/media_runtime_store.dart';


class JobPollingDependencies {
  const JobPollingDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.jobNotifications,
    required this.pendingMediaRefreshController,
    required this.chatJobMessages,
    required this.loadErrors,
    required this.replaceJob,
    required this.replaceGalleryItem,
    required this.syncDeletedScalingSource,
    required this.latestCompletedGalleryItem,
    required this.videoResultPreviewController,
    required this.notifyChanged,
  });

  final AppConnectionStore connection;
  final AppActivityStore activity;
  final JobRuntimeStore jobRuntime;
  final MediaRuntimeStore mediaRuntime;
  final JobNotificationService jobNotifications;
  final PendingMediaRefreshController pendingMediaRefreshController;
  final ChatJobMessageController Function() chatJobMessages;
  final Future<void> Function({bool silent}) loadErrors;
  final void Function(JobStatus job) replaceJob;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(JobStatus job) syncDeletedScalingSource;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
  final VideoResultPreviewController videoResultPreviewController;
  final void Function() notifyChanged;
}

class JobPollingController {
  JobPollingController(this.dependencies)
    : _terminalJobController = TerminalJobHandler(
        TerminalJobHandlerDependencies(
          connection: dependencies.connection,
          activity: dependencies.activity,
          mediaRuntime: dependencies.mediaRuntime,
          jobNotifications: dependencies.jobNotifications,
          chatJobMessages: dependencies.chatJobMessages,
          loadErrors: dependencies.loadErrors,
          replaceGalleryItem: dependencies.replaceGalleryItem,
          syncDeletedScalingSource: dependencies.syncDeletedScalingSource,
          latestCompletedGalleryItem: dependencies.latestCompletedGalleryItem,
          videoResultPreviewController: dependencies.videoResultPreviewController,
          notifyChanged: dependencies.notifyChanged,
        ),
      );
  late final FetchedJobSynchronizer _fetchedJobController =
      FetchedJobSynchronizer(
        FetchedJobSynchronizerDependencies(
          activity: dependencies.activity,
          jobRuntime: dependencies.jobRuntime,
          mediaRuntime: dependencies.mediaRuntime,
          pendingMediaRefreshController: dependencies.pendingMediaRefreshController,
          replaceGalleryItem: dependencies.replaceGalleryItem,
          syncDeletedScalingSource: dependencies.syncDeletedScalingSource,
          latestCompletedGalleryItem: dependencies.latestCompletedGalleryItem,
          videoResultPreviewController: dependencies.videoResultPreviewController,
        ),
      );

  static const _mediaRefreshInterval = Duration(seconds: 2);

  final JobPollingDependencies dependencies;
  final JobStatusFetcher _jobStatusService = const JobStatusFetcher();
  final TerminalJobHandler _terminalJobController;
  final Set<String> _polledJobIds = <String>{};
  Timer? _mediaRefreshTimer;
  bool _mediaRefreshInFlight = false;

  void dispose() {
    _mediaRefreshTimer?.cancel();
  }

  void reset() {
    _polledJobIds.clear();
    _mediaRefreshInFlight = false;
  }

  Future<ImageRecord?> pollJob(
    String jobId, {
    String? expectedResultImageId,
  }) async {
    final client = dependencies.connection.api;
    if (client == null || !_polledJobIds.add(jobId)) {
      return null;
    }

    var shouldResumeNextJob = false;
    try {
      while (true) {
        final job = await _jobStatusService.fetchWithRetry(client, jobId);
        _syncPolledJob(job);
        if (job.isTerminal) {
          shouldResumeNextJob = true;
          return await _handleTerminalJob(
            job,
            expectedResultImageId: expectedResultImageId,
          );
        }
        await _showRunningNotification(job);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (_) {
      await dependencies.jobNotifications.cancelRunningJob(jobId: jobId);
      rethrow;
    } finally {
      _polledJobIds.remove(jobId);
      if (shouldResumeNextJob) {
        unawaited(_resumeNextActiveJob(excludingJobId: jobId));
      }
      syncMediaRefreshTimer();
    }
  }

  void syncMediaRefreshTimer() {
    if (!_shouldRefreshMediaState) {
      _mediaRefreshTimer?.cancel();
      _mediaRefreshTimer = null;
      return;
    }
    if (_mediaRefreshTimer != null) {
      return;
    }
    _mediaRefreshTimer = Timer.periodic(_mediaRefreshInterval, (_) {
      unawaited(_refreshMediaStateSilently());
    });
  }

  void schedulePollingForFirstActiveJob(
    Iterable<JobStatus> sourceJobs, {
    String? excludingJobId,
  }) {
    for (final job in sourceJobs) {
      if (!_shouldPollJob(job, excludingJobId: excludingJobId)) {
        continue;
      }
      _setActiveJob(job);
      unawaited(_pollJobSafely(job.jobId));
      break;
    }
  }

  Future<void> _pollJobSafely(String jobId) async {
    try {
      await pollJob(jobId);
    } catch (_) {
      // Silent refresh can recover active jobs later. Fire-and-forget polling
      // failures should not escape as uncaught async errors.
    }
  }

  void _syncPolledJob(JobStatus job) {
    if (job.isPrimaryWorkflowJob ||
        dependencies.jobRuntime.latestJob?.jobId == job.jobId) {
      dependencies.jobRuntime.latestJob = job;
    }
    dependencies.replaceJob(job);
    if (job.type == 'chat_message') {
      dependencies.chatJobMessages().syncStreamingJob(job);
    }
    final result = job.result;
    if (result != null) {
      dependencies.replaceGalleryItem(result);
      if (result.isReady) {
        dependencies.mediaRuntime.latestImage = result;
      }
    }
    syncMediaRefreshTimer();
    dependencies.notifyChanged();
  }

  Future<ImageRecord?> _handleTerminalJob(
    JobStatus job, {
    String? expectedResultImageId,
  }) async {
    final result = await _terminalJobController.handle(
      job,
      expectedResultImageId: expectedResultImageId,
    );
    syncMediaRefreshTimer();
    return result;
  }

  Future<void> _showRunningNotification(JobStatus job) async {
    if (job.status == 'running' &&
        job.type != 'chat_message' &&
        job.isPrimaryWorkflowJob) {
      await dependencies.jobNotifications.showRunningJob(job);
    }
  }

  Future<void> _refreshMediaStateSilently() async {
    final client = dependencies.connection.api;
    if (client == null) {
      syncMediaRefreshTimer();
      return;
    }
    if (_mediaRefreshInFlight || !_shouldRefreshMediaState) {
      syncMediaRefreshTimer();
      return;
    }

    _mediaRefreshInFlight = true;
    try {
      final fetchedJobs = await client.fetchJobs();
      dependencies.jobRuntime.jobs = fetchedJobs;
      _fetchedJobController.sync(fetchedJobs, setActiveJob: _setActiveJob);
      await dependencies.pendingMediaRefreshController.refresh(client);
      schedulePollingForFirstActiveJob(fetchedJobs);
      dependencies.notifyChanged();
    } catch (_) {
      return;
    } finally {
      _mediaRefreshInFlight = false;
      syncMediaRefreshTimer();
    }
  }

  bool _shouldPollJob(JobStatus job, {String? excludingJobId}) {
    final isActive = job.status == 'queued' || job.status == 'running';
    return isActive &&
        job.jobId != excludingJobId &&
        !_polledJobIds.contains(job.jobId);
  }

  void _setActiveJob(JobStatus job) {
    if (job.isPrimaryWorkflowJob ||
        dependencies.jobRuntime.latestJob?.jobId == job.jobId) {
      dependencies.jobRuntime.latestJob = job;
    }
    dependencies.activity.runningJob = job.canCancel;
    if (job.type == 'chat_message') {
      dependencies.chatJobMessages().ensureTempMessages(job);
      dependencies.chatJobMessages().syncStreamingJob(job);
    }
  }

  Future<void> _resumeNextActiveJob({String? excludingJobId}) async {
    final client = dependencies.connection.api;
    if (client == null) {
      return;
    }

    try {
      final fetchedJobs = await client.fetchJobs();
      dependencies.jobRuntime.jobs = fetchedJobs;
      schedulePollingForFirstActiveJob(
        fetchedJobs,
        excludingJobId: excludingJobId,
      );
      syncMediaRefreshTimer();
      dependencies.notifyChanged();
    } catch (_) {
      return;
    }
  }

  bool get _shouldRefreshMediaState {
    return dependencies.connection.baseUrl.trim().isNotEmpty &&
        (_hasActiveJobs ||
            dependencies.pendingMediaRefreshController.hasPendingMedia ||
            _polledJobIds.isNotEmpty);
  }

  bool get _hasActiveJobs {
    for (final job in dependencies.jobRuntime.jobs) {
      if (job.canCancel) {
        return true;
      }
    }
    return dependencies.jobRuntime.latestJob?.canCancel ?? false;
  }
}
