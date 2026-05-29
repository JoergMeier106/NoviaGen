import 'dart:async';

import '../../models/jobs.dart';
import '../../models/media.dart';
import '../chat_job_message_state.dart';
import '../job_notification_state.dart';
import 'app_fetched_job_synchronizer.dart';
import 'app_job_status_fetcher.dart';
import 'app_pending_media_refresh.dart';
import 'app_terminal_job_handler.dart';
import 'app_video_result_preview_refresher.dart';
import 'runtime/app_activity_state.dart';
import 'runtime/app_connection_state.dart';
import 'runtime/app_job_runtime_state.dart';
import 'runtime/app_media_runtime_state.dart';


class AppJobPollingDependencies {
  const AppJobPollingDependencies({
    required this.connection,
    required this.activity,
    required this.jobRuntime,
    required this.mediaRuntime,
    required this.jobNotifications,
    required this.pendingMediaRefresh,
    required this.chatJobMessages,
    required this.loadErrors,
    required this.replaceJob,
    required this.replaceGalleryItem,
    required this.syncDeletedScalingSource,
    required this.latestCompletedGalleryItem,
    required this.videoResultPreviewRefresher,
    required this.notifyChanged,
  });

  final AppConnectionState connection;
  final AppActivityState activity;
  final AppJobRuntimeState jobRuntime;
  final AppMediaRuntimeState mediaRuntime;
  final JobNotificationState jobNotifications;
  final AppPendingMediaRefresh pendingMediaRefresh;
  final ChatJobMessageState Function() chatJobMessages;
  final Future<void> Function({bool silent}) loadErrors;
  final void Function(JobStatus job) replaceJob;
  final void Function(ImageRecord image) replaceGalleryItem;
  final void Function(JobStatus job) syncDeletedScalingSource;
  final ImageRecord? Function([List<ImageRecord>? items])
  latestCompletedGalleryItem;
  final AppVideoResultPreviewRefresher videoResultPreviewRefresher;
  final void Function() notifyChanged;
}

class AppJobPollingController {
  AppJobPollingController(this.dependencies)
    : _terminalJobHandler = AppTerminalJobHandler(
        AppTerminalJobHandlerDependencies(
          connection: dependencies.connection,
          activity: dependencies.activity,
          mediaRuntime: dependencies.mediaRuntime,
          jobNotifications: dependencies.jobNotifications,
          chatJobMessages: dependencies.chatJobMessages,
          loadErrors: dependencies.loadErrors,
          replaceGalleryItem: dependencies.replaceGalleryItem,
          syncDeletedScalingSource: dependencies.syncDeletedScalingSource,
          latestCompletedGalleryItem: dependencies.latestCompletedGalleryItem,
          videoResultPreviewRefresher: dependencies.videoResultPreviewRefresher,
          notifyChanged: dependencies.notifyChanged,
        ),
      );
  late final AppFetchedJobSynchronizer _fetchedJobSynchronizer =
      AppFetchedJobSynchronizer(
        AppFetchedJobSyncDependencies(
          activity: dependencies.activity,
          jobRuntime: dependencies.jobRuntime,
          mediaRuntime: dependencies.mediaRuntime,
          pendingMediaRefresh: dependencies.pendingMediaRefresh,
          replaceGalleryItem: dependencies.replaceGalleryItem,
          syncDeletedScalingSource: dependencies.syncDeletedScalingSource,
          latestCompletedGalleryItem: dependencies.latestCompletedGalleryItem,
          videoResultPreviewRefresher: dependencies.videoResultPreviewRefresher,
        ),
      );

  static const _mediaRefreshInterval = Duration(seconds: 2);

  final AppJobPollingDependencies dependencies;
  final AppJobStatusFetcher _jobStatusFetcher = const AppJobStatusFetcher();
  final AppTerminalJobHandler _terminalJobHandler;
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
        final job = await _jobStatusFetcher.fetchWithRetry(client, jobId);
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
      unawaited(pollJob(job.jobId));
      break;
    }
  }

  void _syncPolledJob(JobStatus job) {
    dependencies.jobRuntime.latestJob = job;
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
    final result = await _terminalJobHandler.handle(
      job,
      expectedResultImageId: expectedResultImageId,
    );
    syncMediaRefreshTimer();
    return result;
  }

  Future<void> _showRunningNotification(JobStatus job) async {
    if (job.status == 'running' && job.type != 'chat_message') {
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
      _fetchedJobSynchronizer.sync(fetchedJobs, setActiveJob: _setActiveJob);
      await dependencies.pendingMediaRefresh.refresh(client);
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
    dependencies.jobRuntime.latestJob = job;
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
            dependencies.pendingMediaRefresh.hasPendingMedia ||
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
