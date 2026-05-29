import 'package:noviagen/api_client.dart';
import 'package:noviagen/models/jobs.dart';
import 'package:noviagen/models/media.dart';
import 'package:noviagen/features/chat/controllers/chat_job_message_controller.dart';
import 'package:noviagen/app/navigation/app_navigation_controller.dart';
import 'package:noviagen/shared/request_errors.dart';
import 'package:noviagen/features/jobs/persistence/inter_job_delay_persistence.dart';


class JobOperationsController {
  JobOperationsController({
    required this.api,
    required this.setMessage,
    required this.onChanged,
    required this.replaceJob,
    required this.setJobs,
    required this.setLoadingJobs,
    required this.syncDeletedScalingSource,
    required this.schedulePollingForFirstActiveJob,
    required this.syncMediaRefreshTimer,
    required this.setLatestJob,
    required this.latestJob,
    required this.setLatestImage,
    required this.setRunningJob,
    required this.pollJob,
    required this.loadLatestResult,
    required this.chatJobMessages,
    required this.navigation,
    required this.getInterJobDelaySeconds,
    required this.setInterJobDelaySeconds,
  });

  final ApiClient? Function() api;
  final void Function(String? message) setMessage;
  final void Function() onChanged;
  final void Function(JobStatus job) replaceJob;
  final void Function(List<JobStatus> value) setJobs;
  final void Function(bool value) setLoadingJobs;
  final void Function(JobStatus job) syncDeletedScalingSource;
  final void Function(Iterable<JobStatus> jobs)
  schedulePollingForFirstActiveJob;
  final void Function() syncMediaRefreshTimer;
  final void Function(JobStatus? value) setLatestJob;
  final JobStatus? Function() latestJob;
  final void Function(ImageRecord? value) setLatestImage;
  final void Function(bool value) setRunningJob;
  final Future<ImageRecord?> Function(String jobId) pollJob;
  final Future<void> Function({bool silent}) loadLatestResult;
  final ChatJobMessageController chatJobMessages;
  final AppNavigationController navigation;
  final int Function() getInterJobDelaySeconds;
  final void Function(int value) setInterJobDelaySeconds;

  bool clearingFinishedJobs = false;
  bool cancellingAllJobs = false;
  bool updatingShutdownWhenJobsComplete = false;
  bool shutdownWhenJobsComplete = false;
  bool launchRestoreStarted = false;

  Future<void> loadJobs() async {
    final client = api();
    if (client == null) {
      return;
    }

    setLoadingJobs(true);
    onChanged();
    try {
      final fetchedJobs = await client.fetchJobs();
      setJobs(fetchedJobs);
      for (final job in fetchedJobs) {
        syncDeletedScalingSource(job);
      }
      shutdownWhenJobsComplete = await client.fetchShutdownWhenIdle();
      schedulePollingForFirstActiveJob(fetchedJobs);
      syncMediaRefreshTimer();
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t load jobs right now. Please try again.',
      );
    } finally {
      setLoadingJobs(false);
      onChanged();
    }
  }

  Future<void> restoreActiveJobOnLaunch() async {
    final client = api();
    if (client == null || launchRestoreStarted) {
      return;
    }

    launchRestoreStarted = true;
    try {
      final fetchedJobs = await client.fetchJobs();
      setJobs(fetchedJobs);
      for (final job in fetchedJobs) {
        syncDeletedScalingSource(job);
      }
      shutdownWhenJobsComplete = await client.fetchShutdownWhenIdle();
      syncMediaRefreshTimer();

      final activeJob = _firstActiveJob(fetchedJobs);
      if (activeJob != null) {
        await _restoreActiveJob(activeJob);
        return;
      }

      setRunningJob(false);
      if (fetchedJobs.isNotEmpty) {
        final newestJob = await client.getJob(fetchedJobs.first.jobId);
        setLatestJob(newestJob);
        if (newestJob.result?.isReady == true) {
          setLatestImage(newestJob.result);
          onChanged();
          return;
        }
      } else {
        setLatestJob(null);
      }
      await loadLatestResult(silent: true);
    } catch (_) {
      setRunningJob(false);
      await loadLatestResult(silent: true);
    } finally {
      setRunningJob(latestJob()?.canCancel ?? false);
      syncMediaRefreshTimer();
      onChanged();
    }
  }

  Future<void> cancelJob(String jobId) async {
    final client = api();
    if (client == null) {
      return;
    }
    try {
      final updatedJob = await client.cancelJob(jobId);
      replaceJob(updatedJob);
      setMessage(
        updatedJob.status == 'cancelled'
            ? 'Job cancelled.'
            : 'Cancellation requested. Waiting for the backend to stop the job.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t cancel the job right now. Please try again.',
      );
    }
    onChanged();
  }

  Future<void> clearFinishedJobs() async {
    final client = api();
    if (client == null || clearingFinishedJobs) {
      return;
    }
    clearingFinishedJobs = true;
    onChanged();
    try {
      final deleted = await client.clearFinishedJobs();
      await loadJobs();
      setMessage(
        deleted == 1
            ? '1 finished job cleared.'
            : '$deleted finished jobs cleared.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t clear the finished jobs right now. Please try again.',
      );
    } finally {
      clearingFinishedJobs = false;
      onChanged();
    }
  }

  Future<void> cancelAllJobs() async {
    final client = api();
    if (client == null || cancellingAllJobs) {
      return;
    }
    cancellingAllJobs = true;
    onChanged();
    try {
      final cancelled = await client.cancelAllJobs();
      await loadJobs();
      setMessage(
        cancelled == 1
            ? '1 job cancellation requested.'
            : '$cancelled job cancellations requested.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t cancel the active jobs right now. Please try again.',
      );
    } finally {
      cancellingAllJobs = false;
      onChanged();
    }
  }

  Future<void> setShutdownWhenJobsComplete(bool value) async {
    final client = api();
    if (client == null) {
      return;
    }
    updatingShutdownWhenJobsComplete = true;
    onChanged();
    try {
      shutdownWhenJobsComplete = await client.setShutdownWhenIdle(value);
      setMessage(
        shutdownWhenJobsComplete
            ? 'Server host will shut down after queued and running jobs finish.'
            : 'Automatic shutdown after jobs has been disabled.',
      );
    } catch (error) {
      _setRequestError(
        error,
        'Couldn\'t update the shutdown-after-jobs setting right now. Please try again.',
      );
    } finally {
      updatingShutdownWhenJobsComplete = false;
      onChanged();
    }
  }

  Future<void> syncInterJobDelaySetting({bool silent = false}) async {
    final client = api();
    if (client == null) {
      if (!silent) {
        setMessage('Set a backend URL first.');
        onChanged();
      }
      return;
    }
    try {
      final updatedDelay = await client.setInterJobDelaySeconds(
        getInterJobDelaySeconds(),
      );
      if (updatedDelay != getInterJobDelaySeconds()) {
        setInterJobDelaySeconds(updatedDelay);
        await saveInterJobDelaySecondsPreference(updatedDelay);
      }
      if (!silent) {
        setMessage(
          updatedDelay <= 0
              ? 'Cooldown between queued jobs has been disabled.'
              : 'Server will pause ${updatedDelay}s between queued jobs.',
        );
      }
    } catch (error) {
      if (!silent) {
        _setRequestError(
          error,
          'Couldn\'t update the cooldown between queued jobs right now. Please try again.',
        );
      }
    } finally {
      onChanged();
    }
  }

  Future<bool> saveInterJobDelaySeconds(int value) async {
    if (getInterJobDelaySeconds() == value) {
      return false;
    }
    setInterJobDelaySeconds(value);
    await saveInterJobDelaySecondsPreference(value);
    onChanged();
    return true;
  }

  void _setRequestError(Object error, String generalMessage) {
    setMessage(requestErrorMessage(error, generalMessage: generalMessage));
  }

  JobStatus? _firstActiveJob(List<JobStatus> jobs) {
    for (final job in jobs) {
      if (job.status == 'running') {
        return job;
      }
    }
    for (final job in jobs) {
      if (job.status == 'queued') {
        return job;
      }
    }
    return null;
  }

  Future<void> _restoreActiveJob(JobStatus activeJob) async {
    setLatestJob(activeJob);
    setRunningJob(true);
    if (activeJob.type != 'chat_message') {
      navigation.requestOpenGeneratePage();
    } else {
      chatJobMessages.ensureTempMessages(activeJob);
      chatJobMessages.syncStreamingJob(activeJob);
    }
    onChanged();
    await pollJob(activeJob.jobId);
  }
}
